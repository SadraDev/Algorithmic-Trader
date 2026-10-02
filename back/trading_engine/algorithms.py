"""
Trading Algorithms Module.
Contains abstract base algorithm, technical indicators (MACD, RSI), and logical algorithm combiner.
"""

from abc import ABC, abstractmethod
import logging
from typing import List, Literal, Sequence, Optional
import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)


class BaseAlgorithm(ABC):
    """
    Abstract Base Class for all trading signal algorithms.
    Must implement evaluate(dataframe) returning float or int signal.
    """

    @abstractmethod
    def evaluate(self, dataframe: pd.DataFrame) -> float:
        """
        Evaluates input price dataframe and returns a signal (-1.0 to 1.0).

        :param dataframe: pandas DataFrame containing price candles ('close', 'open', 'high', 'low')
        :return: Float signal bounded in [-1.0, 1.0]
        """
        pass


class MACDCrossover(BaseAlgorithm):
    """
    MACD Crossover Trading Algorithm.
    Calculates MACD Line, Signal Line, and Histogram.
    Generates signals when MACD crosses Signal line.
    """

    def __init__(self, fast_period: int = 12, slow_period: int = 26, signal_period: int = 9) -> None:
        if fast_period >= slow_period:
            raise ValueError("fast_period must be smaller than slow_period")
        self.fast_period = fast_period
        self.slow_period = slow_period
        self.signal_period = signal_period

    def evaluate(self, dataframe: pd.DataFrame) -> float:
        """
        Evaluates MACD crossover on price dataframe.
        """
        if dataframe is None or len(dataframe) < (self.slow_period + self.signal_period):
            logger.warning("Insufficient data length for MACD calculation (min required: %d)",
                           self.slow_period + self.signal_period)
            return 0.0

        close_prices = dataframe['close']

        # Calculate Exponential Moving Averages
        ema_fast = close_prices.ewm(span=self.fast_period, adjust=False).mean()
        ema_slow = close_prices.ewm(span=self.slow_period, adjust=False).mean()

        macd_line = ema_fast - ema_slow
        signal_line = macd_line.ewm(span=self.signal_period, adjust=False).mean()
        histogram = macd_line - signal_line

        # Check last two complete candles for crossover
        curr_hist = histogram.iloc[-1]
        prev_hist = histogram.iloc[-2]

        if prev_hist <= 0 < curr_hist:
            return 1.0
        if prev_hist >= 0 > curr_hist:
            return -1.0

        return 0.0


class RSIOversold(BaseAlgorithm):
    """
    RSI Oversold/Overbought Trading Algorithm.
    Generates signal when RSI crosses or stays in oversold (< threshold) or overbought (> threshold) territory.
    """

    def __init__(self, period: int = 14, oversold: float = 30.0, overbought: float = 70.0) -> None:
        if oversold >= overbought:
            raise ValueError("oversold threshold must be less than overbought threshold")
        self.period = period
        self.oversold = oversold
        self.overbought = overbought

    def evaluate(self, dataframe: pd.DataFrame) -> float:
        """
        Evaluates RSI on price dataframe.
        """
        if dataframe is None or len(dataframe) < (self.period + 2):
            logger.warning("Insufficient data length for RSI calculation (min required: %d)", self.period + 2)
            return 0.0

        close_prices = dataframe['close']
        delta = close_prices.diff()

        # Gain and loss series
        gain = (delta.where(delta > 0, 0.0)).to_numpy()
        loss = (-delta.where(delta < 0, 0.0)).to_numpy()

        # Exponential moving average of gain/loss (Wilder's smoothing)
        avg_gain = pd.Series(gain, index=close_prices.index).ewm(alpha=1/self.period, adjust=False).mean()
        avg_loss = pd.Series(loss, index=close_prices.index).ewm(alpha=1/self.period, adjust=False).mean()

        rs = avg_gain / (avg_loss.replace(0, 1e-10))
        rsi = 100.0 - (100.0 / (1.0 + rs))

        curr_rsi = rsi.iloc[-1]
        prev_rsi = rsi.iloc[-2]

        if curr_rsi < self.oversold or (prev_rsi <= self.oversold < curr_rsi):
            return 1.0
        if curr_rsi > self.overbought or (prev_rsi >= self.overbought > curr_rsi):
            return -1.0

        return 0.0


class AlgorithmCombiner(BaseAlgorithm):
    """
    Consolidates multiple indicator signals into a single trade signal (-1, 0, 1) based on
    three distinct logic gates (WEIGHTED, AND, OR) and a configurable threshold n.
    """

    def __init__(
        self,
        algorithms: Sequence[BaseAlgorithm],
        weights: Optional[Sequence[float]] = None,
        operator: Literal['WEIGHTED', 'AND', 'OR'] = 'WEIGHTED',
        signal_threshold: float = 0.5
    ) -> None:
        if not algorithms:
            raise ValueError("At least one algorithm must be provided to AlgorithmCombiner")

        op_upper = operator.upper()
        if op_upper not in ('WEIGHTED', 'AND', 'OR'):
            raise ValueError(f"Operator must be 'WEIGHTED', 'AND', or 'OR', got '{operator}'")

        self.algorithms: List[BaseAlgorithm] = list(algorithms)
        self.weights: List[float] = list(weights) if weights and len(weights) == len(algorithms) else [1.0 / len(algorithms)] * len(algorithms)
        self.operator: Literal['WEIGHTED', 'AND', 'OR'] = op_upper  # type: ignore
        self.signal_threshold: float = max(0.01, min(1.0, float(signal_threshold)))

    def calculate_composite_score(self, dataframe: pd.DataFrame) -> float:
        """
        Calculates continuous composite score bounded in [-1.0, 1.0].
        """
        signals = [alg.evaluate(dataframe) for alg in self.algorithms]
        total_weight = sum(self.weights) if sum(self.weights) > 0 else 1.0
        score = sum(s * w for s, w in zip(signals, self.weights)) / total_weight
        return max(-1.0, min(1.0, float(score)))

    def evaluate(self, dataframe: pd.DataFrame) -> float:
        """
        Evaluates child indicators and processes output through logic gates against threshold n.
        """
        signals = [alg.evaluate(dataframe) for alg in self.algorithms]
        n = self.signal_threshold

        logger.debug(
            "AlgorithmCombiner gate [%s] signals: %s, weights: %s, threshold n: %.2f",
            self.operator,
            signals,
            self.weights,
            n
        )

        if self.operator == 'WEIGHTED':
            # Weighted average = sum(signal_i * weight_i) / sum(weight_i)
            total_weight = sum(self.weights) if sum(self.weights) > 0 else 1.0
            composite_score = sum(s * w for s, w in zip(signals, self.weights)) / total_weight

            if composite_score >= n:
                return 1.0
            elif composite_score <= -n:
                return -1.0
            return 0.0

        elif self.operator == 'AND':
            # Triggers Long if EVERY selected indicator >= n. Triggers Short if EVERY selected indicator <= -n.
            if all(s >= n for s in signals):
                return 1.0
            elif all(s <= -n for s in signals):
                return -1.0
            return 0.0

        elif self.operator == 'OR':
            # Triggers Long if ANY selected indicator >= n. Triggers Short if ANY selected indicator <= -n.
            has_long = any(s >= n for s in signals)
            has_short = any(s <= -n for s in signals)

            if has_long and not has_short:
                return 1.0
            elif has_short and not has_long:
                return -1.0
            return 0.0

        return 0.0
