from django.test import TestCase
import pandas as pd
from types import SimpleNamespace

from trading_engine.strategies import OpenStrategy, CloseStrategy


class StrategiesTestCase(TestCase):

    def setUp(self) -> None:
        self.open_strat = OpenStrategy(risk_percentage=1.0, sl_tp_ratio=2.0)
        self.close_strat = CloseStrategy(choch_window=5)

    def test_bullish_engulfing_validation(self) -> None:
        # Construct bullish engulfing setup:
        # Prev: open=1.1000, close=1.0950 (bearish body = 0.0050)
        # Curr: open=1.0940, close=1.1020 (bullish body = 0.0080, engulfs prev)
        df_bullish = pd.DataFrame([
            {'open': 1.1000, 'high': 1.1010, 'low': 1.0945, 'close': 1.0950},
            {'open': 1.0940, 'high': 1.1025, 'low': 1.0935, 'close': 1.1020},
        ])

        self.assertTrue(self.open_strat.validate_trigger(1, df_bullish))
        self.assertFalse(self.open_strat.validate_trigger(-1, df_bullish))

    def test_bearish_engulfing_validation(self) -> None:
        # Construct bearish engulfing setup:
        # Prev: open=1.0950, close=1.1000 (bullish)
        # Curr: open=1.1010, close=1.0930 (bearish, engulfs prev)
        df_bearish = pd.DataFrame([
            {'open': 1.0950, 'high': 1.1005, 'low': 1.0945, 'close': 1.1000},
            {'open': 1.1010, 'high': 1.1015, 'low': 1.0925, 'close': 1.0930},
        ])

        self.assertTrue(self.open_strat.validate_trigger(-1, df_bearish))
        self.assertFalse(self.open_strat.validate_trigger(1, df_bearish))

    def test_calculate_sl_tp(self) -> None:
        df = pd.DataFrame([
            {'open': 1.1000, 'high': 1.1010, 'low': 1.0945, 'close': 1.0950},
            {'open': 1.0940, 'high': 1.1025, 'low': 1.0935, 'close': 1.1020},
        ])

        entry = 1.1020
        sl, tp = self.open_strat.calculate_sl_tp(signal=1, entry_price=entry, dataframe=df, sl_tp_ratio=2.0)
        self.assertLess(sl, entry)
        self.assertGreater(tp, entry)
        self.assertAlmostEqual(tp - entry, (entry - sl) * 2.0, places=4)

    def test_position_size_calculation(self) -> None:
        balance = 10000.0
        risk_pct = 1.0  # $100 risk
        entry = 1.1000
        sl = 1.0950     # 50 pips distance

        sym_info = SimpleNamespace(
            trade_tick_size=0.00001,
            trade_tick_value=1.0,
            volume_min=0.01,
            volume_max=100.0,
            volume_step=0.01
        )

        lots = self.open_strat.calculate_position_size(
            account_balance=balance,
            risk_percentage=risk_pct,
            entry_price=entry,
            sl_price=sl,
            symbol_info=sym_info
        )
        self.assertGreater(lots, 0.0)

    def test_close_strategy_choch_buy(self) -> None:
        # Window of candles with lows around 1.1000, then latest candle drops to 1.0950 (breaking low)
        data = [
            {'close': 1.1020, 'high': 1.1030, 'low': 1.1000},
            {'close': 1.1015, 'high': 1.1025, 'low': 1.1005},
            {'close': 1.1010, 'high': 1.1020, 'low': 1.1002},
            {'close': 1.1025, 'high': 1.1035, 'low': 1.1010},
            {'close': 1.1018, 'high': 1.1028, 'low': 1.1008},
            {'close': 1.1020, 'high': 1.1030, 'low': 1.1005},
            {'close': 1.0950, 'high': 1.1000, 'low': 1.0940},  # Drop breaking 1.1000
        ]
        df = pd.DataFrame(data)

        # BUY position (type=0)
        buy_position = SimpleNamespace(ticket=123456, type=0, symbol="EURUSD")
        should_close = self.close_strat.evaluate_position(buy_position, df)
        self.assertTrue(should_close)

    def test_close_strategy_choch_sell(self) -> None:
        # Window of candles with highs around 1.1000, then latest candle spikes to 1.1050 (breaking high)
        data = [
            {'close': 1.0980, 'high': 1.1000, 'low': 1.0950},
            {'close': 1.0985, 'high': 1.0998, 'low': 1.0960},
            {'close': 1.0990, 'high': 1.1002, 'low': 1.0970},
            {'close': 1.0982, 'high': 1.0995, 'low': 1.0965},
            {'close': 1.0988, 'high': 1.1000, 'low': 1.0972},
            {'close': 1.0992, 'high': 1.1001, 'low': 1.0980},
            {'close': 1.1050, 'high': 1.1060, 'low': 1.0995},  # Spike breaking 1.1002
        ]
        df = pd.DataFrame(data)

        # SELL position (type=1)
        sell_position = SimpleNamespace(ticket=654321, type=1, symbol="EURUSD")
        should_close = self.close_strat.evaluate_position(sell_position, df)
        self.assertTrue(should_close)
