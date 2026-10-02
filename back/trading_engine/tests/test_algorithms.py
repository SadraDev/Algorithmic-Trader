from django.test import TestCase
import pandas as pd
import numpy as np

from trading_engine.algorithms import MACDCrossover, RSIOversold, AlgorithmCombiner, BaseAlgorithm


class MockAlgorithm(BaseAlgorithm):
    def __init__(self, return_signal: float) -> None:
        self.return_signal = return_signal

    def evaluate(self, dataframe: pd.DataFrame) -> float:
        return self.return_signal


class AlgorithmsTestCase(TestCase):

    def setUp(self) -> None:
        # Create a sample price series for testing indicators
        np.random.seed(42)
        n = 50
        dates = pd.date_range(start='2023-01-01', periods=n, freq='5min')

        # Upward trending prices to generate technical signals
        close = 100.0 + np.cumsum(np.random.normal(0.2, 1.0, size=n))
        open_p = close - np.random.normal(0.0, 0.5, size=n)
        high = np.maximum(close, open_p) + 0.5
        low = np.minimum(close, open_p) - 0.5

        self.df = pd.DataFrame({
            'time': dates,
            'open': open_p,
            'high': high,
            'low': low,
            'close': close,
            'tick_volume': 100
        })

    def test_macd_initialization_validation(self) -> None:
        with self.assertRaises(ValueError):
            MACDCrossover(fast_period=26, slow_period=12)

    def test_macd_evaluation(self) -> None:
        macd = MACDCrossover(fast_period=12, slow_period=26, signal_period=9)
        signal = macd.evaluate(self.df)
        self.assertIn(signal, [-1, 0, 1])

        # Test short dataframe
        short_df = self.df.head(10)
        self.assertEqual(macd.evaluate(short_df), 0)

    def test_rsi_initialization_validation(self) -> None:
        with self.assertRaises(ValueError):
            RSIOversold(oversold=70.0, overbought=30.0)

    def test_rsi_evaluation(self) -> None:
        rsi = RSIOversold(period=14, oversold=30.0, overbought=70.0)
        signal = rsi.evaluate(self.df)
        self.assertIn(signal, [-1, 0, 1])

    def test_combiner_and_operator(self) -> None:
        alg1 = MockAlgorithm(1.0)
        alg2 = MockAlgorithm(1.0)
        combiner = AlgorithmCombiner(algorithms=[alg1, alg2], operator='AND')
        self.assertEqual(combiner.evaluate(self.df), 1)

        # Disagreement
        alg3 = MockAlgorithm(0.0)
        combiner_disagree = AlgorithmCombiner(algorithms=[alg1, alg3], operator='AND')
        self.assertEqual(combiner_disagree.evaluate(self.df), 0)

    def test_combiner_or_operator(self) -> None:
        alg1 = MockAlgorithm(1.0)
        alg2 = MockAlgorithm(0.0)
        combiner = AlgorithmCombiner(algorithms=[alg1, alg2], operator='OR')
        self.assertEqual(combiner.evaluate(self.df), 1)

        # Conflicting signals cancel out
        alg3 = MockAlgorithm(-1.0)
        combiner_conflict = AlgorithmCombiner(algorithms=[alg1, alg3], operator='OR')
        self.assertEqual(combiner_conflict.evaluate(self.df), 0)

    def test_combiner_signal_threshold(self) -> None:
        # Continuous signals at 0.6 >= threshold 0.5 -> triggers 1
        alg1 = MockAlgorithm(0.6)
        alg2 = MockAlgorithm(0.7)
        combiner = AlgorithmCombiner(algorithms=[alg1, alg2], operator='AND', signal_threshold=0.5)
        self.assertEqual(combiner.evaluate(self.df), 1)

        # Signal at 0.3 < threshold 0.5 -> fails AND condition
        alg_low = MockAlgorithm(0.3)
        combiner_low = AlgorithmCombiner(algorithms=[alg1, alg_low], operator='AND', signal_threshold=0.5)
        self.assertEqual(combiner_low.evaluate(self.df), 0)

        # Signal at 0.3 >= custom threshold 0.2 -> passes AND condition
        combiner_custom_thresh = AlgorithmCombiner(algorithms=[alg1, alg_low], operator='AND', signal_threshold=0.2)
        self.assertEqual(combiner_custom_thresh.evaluate(self.df), 1)

    def test_combiner_invalid_inputs(self) -> None:
        with self.assertRaises(ValueError):
            AlgorithmCombiner(algorithms=[])

        with self.assertRaises(ValueError):
            AlgorithmCombiner(algorithms=[MockAlgorithm(1)], operator='XOR')  # type: ignore
