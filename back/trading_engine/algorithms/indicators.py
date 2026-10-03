import logging
from typing import Dict, Any, List, Union
import numpy as np
import pandas as pd

from .base import BaseAlgorithm
from .combiner import AlgorithmCombiner

logger = logging.getLogger(__name__)


class RSIIndicator(BaseAlgorithm):
    """
    RSI Technical Indicator returning continuous normalized series in [-1.0, 1.0].
    """

    def __init__(self, period: int = 14) -> None:
        self.period = period

    def calculate_series(self, dataframe: pd.DataFrame) -> pd.Series:
        if dataframe is None or len(dataframe) < (self.period + 2):
            return pd.Series(0.0, index=dataframe.index if dataframe is not None else None)

        close_prices = dataframe['close']
        delta = close_prices.diff()

        gain = delta.where(delta > 0, 0.0)
        loss = -delta.where(delta < 0, 0.0)

        avg_gain = gain.ewm(alpha=1.0 / self.period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1.0 / self.period, adjust=False).mean()

        rs = avg_gain / avg_loss.replace(0, 1e-10)
        rsi = 100.0 - (100.0 / (1.0 + rs))

        normalized = (rsi - 50.0) / 50.0
        return normalized.clip(-1.0, 1.0).fillna(0.0)

    def evaluate(self, dataframe: pd.DataFrame) -> pd.Series:
        return self.calculate_series(dataframe)


class StochasticIndicator(BaseAlgorithm):
    """
    Stochastic Oscillator (%K & %D) returning normalized series in [-1.0, 1.0].
    """

    def __init__(self, k_period: int = 14, d_period: int = 3) -> None:
        self.k_period = k_period
        self.d_period = d_period

    def calculate_series(self, dataframe: pd.DataFrame) -> pd.Series:
        if dataframe is None or len(dataframe) < (self.k_period + self.d_period):
            return pd.Series(0.0, index=dataframe.index if dataframe is not None else None)

        low_min = dataframe['low'].rolling(window=self.k_period).min()
        high_max = dataframe['high'].rolling(window=self.k_period).max()

        k_fast = 100.0 * (dataframe['close'] - low_min) / (high_max - low_min + 1e-10)
        d_slow = k_fast.rolling(window=self.d_period).mean()

        normalized = (d_slow - 50.0) / 50.0
        return normalized.clip(-1.0, 1.0).fillna(0.0)

    def evaluate(self, dataframe: pd.DataFrame) -> pd.Series:
        return self.calculate_series(dataframe)


class MACDIndicator(BaseAlgorithm):
    """
    MACD Z-Score Indicator squashing histogram via rolling Z-score into [-1.0, 1.0].
    """

    def __init__(self, fast: int = 12, slow: int = 26, signal: int = 9, z_window: int = 100) -> None:
        self.fast = fast
        self.slow = slow
        self.signal = signal
        self.z_window = z_window

    def calculate_series(self, dataframe: pd.DataFrame) -> pd.Series:
        if dataframe is None or len(dataframe) < (self.slow + self.signal):
            return pd.Series(0.0, index=dataframe.index if dataframe is not None else None)

        close = dataframe['close']
        ema_fast = close.ewm(span=self.fast, adjust=False).mean()
        ema_slow = close.ewm(span=self.slow, adjust=False).mean()

        macd_line = ema_fast - ema_slow
        signal_line = macd_line.ewm(span=self.signal, adjust=False).mean()
        histogram = macd_line - signal_line

        rolling_mean = histogram.rolling(window=self.z_window, min_periods=10).mean()
        rolling_std = histogram.rolling(window=self.z_window, min_periods=10).std().replace(0, 1e-10)

        z_score = (histogram - rolling_mean) / rolling_std
        squashed = np.tanh(z_score)

        return pd.Series(squashed, index=dataframe.index).fillna(0.0)

    def evaluate(self, dataframe: pd.DataFrame) -> pd.Series:
        return self.calculate_series(dataframe)


class BollingerBandsIndicator(BaseAlgorithm):
    """
    Bollinger Bands %B Indicator returning normalized output series in [-1.0, 1.0].
    """

    def __init__(self, period: int = 20, std_dev: float = 2.0) -> None:
        self.period = period
        self.std_dev = std_dev

    def calculate_series(self, dataframe: pd.DataFrame) -> pd.Series:
        if dataframe is None or len(dataframe) < self.period:
            return pd.Series(0.0, index=dataframe.index if dataframe is not None else None)

        close = dataframe['close']
        sma = close.rolling(window=self.period).mean()
        std = close.rolling(window=self.period).std().replace(0, 1e-10)

        upper = sma + (std * self.std_dev)
        lower = sma - (std * self.std_dev)

        percent_b = (close - lower) / (upper - lower + 1e-10)
        normalized = (percent_b - 0.5) * 2.0

        return normalized.clip(-1.0, 1.0).fillna(0.0)

    def evaluate(self, dataframe: pd.DataFrame) -> pd.Series:
        return self.calculate_series(dataframe)


class WeightedCombiner:
    """
    Backwards-compatible wrapper accepting {indicator: weight_float} dictionary.
    """

    def __init__(self, weights_dict: Dict[Any, float]) -> None:
        total_weight = sum(weights_dict.values())
        if abs(total_weight - 1.0) > 1e-4:
            raise ValueError(f"Total weights must equal 1.0, got {total_weight}")

        self.algorithms = list(weights_dict.keys())
        self.weights = list(weights_dict.values())

    def evaluate(self, dataframe: pd.DataFrame) -> pd.Series:
        series_list = []
        for alg, w in zip(self.algorithms, self.weights):
            if hasattr(alg, 'calculate_series'):
                s = alg.calculate_series(dataframe)
            else:
                res = alg.evaluate(dataframe)
                s = res if isinstance(res, pd.Series) else pd.Series(res, index=dataframe.index)
            series_list.append(s * float(w))

        combined = sum(series_list)
        return pd.Series(combined, index=dataframe.index if dataframe is not None else None).clip(-1.0, 1.0)
