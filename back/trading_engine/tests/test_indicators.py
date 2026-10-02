from django.test import TestCase
import pandas as pd
import numpy as np

from trading_engine.indicators import (
    RSIIndicator,
    StochasticIndicator,
    MACDIndicator,
    BollingerBandsIndicator,
    WeightedCombiner
)


class IndicatorsTestCase(TestCase):

    def setUp(self) -> None:
        np.random.seed(42)
        n = 120
        dates = pd.date_range(start='2023-01-01', periods=n, freq='5min')
        close = 1.1000 + np.cumsum(np.random.normal(0.0001, 0.0010, size=n))
        open_p = close - np.random.normal(0.0, 0.0005, size=n)
        high = np.maximum(close, open_p) + 0.0005
        low = np.minimum(close, open_p) - 0.0005

        self.df = pd.DataFrame({
            'time': dates,
            'open': open_p,
            'high': high,
            'low': low,
            'close': close,
        })

    def test_rsi_indicator_bounds(self) -> None:
        rsi_ind = RSIIndicator(period=14)
        signals = rsi_ind.evaluate(self.df)

        self.assertIsInstance(signals, pd.Series)
        self.assertEqual(len(signals), len(self.df))
        self.assertTrue((signals >= -1.0).all() and (signals <= 1.0).all())

    def test_stochastic_indicator_bounds(self) -> None:
        stoch_ind = StochasticIndicator(k_period=14, d_period=3)
        signals = stoch_ind.evaluate(self.df)

        self.assertIsInstance(signals, pd.Series)
        self.assertEqual(len(signals), len(self.df))
        self.assertTrue((signals >= -1.0).all() and (signals <= 1.0).all())

    def test_macd_indicator_bounds(self) -> None:
        macd_ind = MACDIndicator(fast=12, slow=26, signal=9, z_window=50)
        signals = macd_ind.evaluate(self.df)

        self.assertIsInstance(signals, pd.Series)
        self.assertEqual(len(signals), len(self.df))
        self.assertTrue((signals >= -1.0).all() and (signals <= 1.0).all())

    def test_bollinger_bands_indicator_bounds(self) -> None:
        bb_ind = BollingerBandsIndicator(period=20, std_dev=2.0)
        signals = bb_ind.evaluate(self.df)

        self.assertIsInstance(signals, pd.Series)
        self.assertEqual(len(signals), len(self.df))
        self.assertTrue((signals >= -1.0).all() and (signals <= 1.0).all())

    def test_weighted_combiner_validation(self) -> None:
        rsi = RSIIndicator(14)
        macd = MACDIndicator(12, 26, 9)

        # Valid weight sum = 1.0
        combiner = WeightedCombiner({rsi: 0.4, macd: 0.6})
        signals = combiner.evaluate(self.df)
        self.assertEqual(len(signals), len(self.df))
        self.assertTrue((signals >= -1.0).all() and (signals <= 1.0).all())

        # Invalid weight sum != 1.0
        with self.assertRaises(ValueError):
            WeightedCombiner({rsi: 0.5, macd: 0.8})
