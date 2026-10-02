from django.test import TestCase
from unittest.mock import patch, MagicMock
from types import SimpleNamespace
import pandas as pd

from trading_engine.executor import TradingExecutor, execute_trading_cycle
from trading_engine.algorithms import AlgorithmCombiner, BaseAlgorithm


class AlwaysLongAlgorithm(BaseAlgorithm):
    def evaluate(self, dataframe: pd.DataFrame) -> int:
        return 1


class ExecutorTestCase(TestCase):

    @patch('trading_engine.mt5_client.MT5Client.copy_rates_from_pos')
    @patch('trading_engine.mt5_client.MT5Client.symbol_info_tick')
    @patch('trading_engine.mt5_client.MT5Client.symbol_info')
    @patch('trading_engine.mt5_client.MT5Client.account_info')
    @patch('trading_engine.mt5_client.MT5Client.order_send')
    @patch('trading_engine.mt5_client.MT5Client.positions_get')
    def test_run_execution_cycle_full_flow(
        self,
        mock_positions,
        mock_order_send,
        mock_account_info,
        mock_symbol_info,
        mock_tick,
        mock_rates
    ) -> None:
        # 1. Mock rates returning bullish engulfing candles
        df_bullish = pd.DataFrame([
            {'time': '2023-01-01 00:00', 'open': 1.1000, 'high': 1.1010, 'low': 1.0945, 'close': 1.0950, 'tick_volume': 100},
            {'time': '2023-01-01 00:05', 'open': 1.0940, 'high': 1.1025, 'low': 1.0935, 'close': 1.1020, 'tick_volume': 150},
        ] * 20)  # repeat to satisfy min length
        mock_rates.return_value = df_bullish

        # 2. Mock symbol tick & info
        mock_tick.return_value = SimpleNamespace(ask=1.1020, bid=1.1018)
        mock_symbol_info.return_value = SimpleNamespace(
            trade_tick_size=0.00001,
            trade_tick_value=1.0,
            volume_min=0.01,
            volume_max=100.0,
            volume_step=0.01
        )
        mock_account_info.return_value = SimpleNamespace(balance=10000.0)

        # 3. Mock order send response
        mock_order_send.return_value = SimpleNamespace(
            retcode=10009,  # TRADE_RETCODE_DONE
            deal=1001,
            order=2002,
            price=1.1020,
            volume=0.10
        )

        # 4. Mock open positions
        mock_positions.return_value = []

        combiner = AlgorithmCombiner(
            algorithms=[AlwaysLongAlgorithm()],
            operator='OR'
        )

        executor = TradingExecutor(
            symbol="EURUSD",
            timeframe=5,
            risk_percentage=1.0,
            sl_tp_ratio=2.0,
            combiner=combiner
        )

        summary = executor.run_execution_cycle()

        self.assertEqual(summary["symbol"], "EURUSD")
        self.assertEqual(summary["signal"], 1)
        self.assertTrue(summary["trigger_valid"])
        self.assertTrue(summary["order_executed"])
        self.assertEqual(summary["order_result"]["deal"], 1001)

    def test_convenience_execute_trading_cycle(self) -> None:
        with patch('trading_engine.executor.TradingExecutor.run_execution_cycle') as mock_run:
            mock_run.return_value = {"status": "ok"}
            res = execute_trading_cycle(symbol="GBPUSD", timeframe=15)
            self.assertEqual(res, {"status": "ok"})
