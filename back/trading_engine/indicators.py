"""
Normalized Continuous-Signal Indicators Module.
Provides BaseIndicator, Bounded Oscillators, Unbounded Dynamic Normalization,
Price Deviation Indicators, and WeightedCombiner.
Outputs are pandas Series of floats strictly bounded in [-1.0, 1.0].
"""

from abc import ABC, abstractmethod
import math
from typing import Dict, Any, Optional
import numpy as np
import pandas as pd


class BaseIndicator(ABC):
    """
    Abstract Base Class for all normalized continuous-signal indicators.
    Output Series must be bounded strictly between -1.0 and 1.0:
     -1.0 : Maximum Bearish / Overbought / Sell Pressure
      0.0 : Neutral / Equilibrium
     +1.0 : Maximum Bullish / Oversold / Buy Pressure
    """

    @abstractmethod
    def evaluate(self, df: pd.DataFrame) -> pd.Series:
        """
        Evaluates input price DataFrame and returns a normalized signal Series [-1.0, 1.0].

        :param df: pandas DataFrame containing price candles ('close', 'high', 'low', 'open')
        :return: pandas Series of float signals bounded in [-1.0, 1.0]
        """
        pass


class RSIIndicator(BaseIndicator):
    """
    Normalized Relative Strength Index (RSI) Indicator.
    Transforms standard RSI (0 to 100) linearly into [-1.0, 1.0].
    """

    def __init__(self, period: int = 14) -> None:
        if period < 1:
            raise ValueError("period must be >= 1")
        self.period = period

    def evaluate(self, df: pd.DataFrame) -> pd.Series:
        if df is None or df.empty or 'close' not in df.columns:
            return pd.Series(dtype=float)

        close = df['close']
        delta = close.diff()

        gain = delta.where(delta > 0, 0.0)
        loss = -delta.where(delta < 0, 0.0)

        # Exponential moving average of gains/losses (Wilder's smoothing)
        avg_gain = gain.ewm(alpha=1.0 / self.period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1.0 / self.period, adjust=False).mean()

        rs = avg_gain / (avg_loss.replace(0.0, 1e-10))
        rsi = 100.0 - (100.0 / (1.0 + rs))

        # Fill initial NaN values with neutral 50.0
        rsi = rsi.fillna(50.0)

        # Linear transformation: (RSI - 50) / 50 -> maps [0, 100] to [-1.0, 1.0]
        normalized_signal = (rsi - 50.0) / 50.0

        return normalized_signal.clip(-1.0, 1.0)


class StochasticIndicator(BaseIndicator):
    """
    Normalized Stochastic Oscillator Indicator.
    Calculates %K line (0 to 100) and maps it linearly into [-1.0, 1.0].
    """

    def __init__(self, k_period: int = 14, d_period: int = 3) -> None:
        if k_period < 1 or d_period < 1:
            raise ValueError("Periods must be >= 1")
        self.k_period = k_period
        self.d_period = d_period

    def evaluate(self, df: pd.DataFrame) -> pd.Series:
        if df is None or df.empty or not {'close', 'high', 'low'}.issubset(df.columns):
            return pd.Series(dtype=float)

        close = df['close']
        low_min = df['low'].rolling(window=self.k_period, min_periods=1).min()
        high_max = df['high'].rolling(window=self.k_period, min_periods=1).max()

        denom = (high_max - low_min).replace(0.0, 1e-10)
        stoch_k = 100.0 * ((close - low_min) / denom)
        stoch_k = stoch_k.fillna(50.0)

        # Linear transformation: (StochK - 50) / 50 -> maps [0, 100] to [-1.0, 1.0]
        normalized_signal = (stoch_k - 50.0) / 50.0

        return normalized_signal.clip(-1.0, 1.0)


class MACDIndicator(BaseIndicator):
    """
    Normalized Moving Average Convergence Divergence (MACD) Indicator.
    Normalizes MACD Histogram via rolling Z-score and squashes using np.tanh().
    """

    def __init__(self, fast: int = 12, slow: int = 26, signal: int = 9, z_window: int = 100) -> None:
        if fast >= slow:
            raise ValueError("fast period must be smaller than slow period")
        if signal < 1 or z_window < 2:
            raise ValueError("signal period must be >= 1 and z_window >= 2")

        self.fast = fast
        self.slow = slow
        self.signal = signal
        self.z_window = z_window

    def evaluate(self, df: pd.DataFrame) -> pd.Series:
        if df is None or df.empty or 'close' not in df.columns:
            return pd.Series(dtype=float)

        close = df['close']
        ema_fast = close.ewm(span=self.fast, adjust=False).mean()
        ema_slow = close.ewm(span=self.slow, adjust=False).mean()

        macd_line = ema_fast - ema_slow
        signal_line = macd_line.ewm(span=self.signal, adjust=False).mean()
        histogram = macd_line - signal_line

        # Compute rolling Z-score over z_window
        rolling_mean = histogram.rolling(window=self.z_window, min_periods=1).mean()
        rolling_std = histogram.rolling(window=self.z_window, min_periods=1).std().fillna(1.0).replace(0.0, 1e-10)

        z_score = (histogram - rolling_mean) / rolling_std
        z_score = z_score.fillna(0.0)

        # Apply np.tanh() to squash Z-score smoothly into [-1.0, 1.0]
        normalized_signal = pd.Series(np.tanh(z_score), index=close.index)

        return normalized_signal.clip(-1.0, 1.0)


class BollingerBandsIndicator(BaseIndicator):
    """
    Normalized Bollinger Bands Deviation Indicator.
    Measures closing price relative to upper and lower bands and squashes
    extreme deviations using np.tanh().
    Oversold (below lower band) -> approaches +1.0 (Buy)
    Overbought (above upper band) -> approaches -1.0 (Sell)
    """

    def __init__(self, period: int = 20, std_dev: float = 2.0) -> None:
        if period < 1 or std_dev <= 0:
            raise ValueError("period must be >= 1 and std_dev > 0")
        self.period = period
        self.std_dev = std_dev

    def evaluate(self, df: pd.DataFrame) -> pd.Series:
        if df is None or df.empty or 'close' not in df.columns:
            return pd.Series(dtype=float)

        close = df['close']
        sma = close.rolling(window=self.period, min_periods=1).mean()
        rolling_std = close.rolling(window=self.period, min_periods=1).std().fillna(1.0).replace(0.0, 1e-10)

        # Deviation distance normalized by band width std_dev * std
        deviation = (sma - close) / (rolling_std * self.std_dev)
        deviation = deviation.fillna(0.0)

        # Apply np.tanh() to squash deviation smoothly into [-1.0, 1.0]
        normalized_signal = pd.Series(np.tanh(deviation), index=close.index)

        return normalized_signal.clip(-1.0, 1.0)


class WeightedCombiner(BaseIndicator):
    """
    Aggregates multiple continuous indicators using specified normalized weights.
    Enforces validation that sum of weights equals exactly 1.0.
    """

    def __init__(self, weights: Dict[BaseIndicator, float]) -> None:
        if not weights:
            raise ValueError("weights dictionary cannot be empty")

        total_weight = sum(weights.values())
        if not math.isclose(total_weight, 1.0, abs_tol=1e-5):
            raise ValueError(f"Sum of indicator weights must equal 1.0, got {total_weight:.6f}")

        self.weights: Dict[BaseIndicator, float] = weights

    def evaluate(self, df: pd.DataFrame) -> pd.Series:
        if df is None or df.empty:
            return pd.Series(dtype=float)

        combined_series = pd.Series(0.0, index=df.index)

        for indicator, weight in self.weights.items():
            ind_signal = indicator.evaluate(df)
            combined_series = combined_series.add(ind_signal * weight, fill_value=0.0)

        return combined_series.clip(-1.0, 1.0)
