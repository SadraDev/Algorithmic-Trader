from django.test import TestCase
from unittest.mock import patch, MagicMock
from types import SimpleNamespace
import numpy as np

from trading_engine.mt5_client import MT5Client


class MT5ClientTestCase(TestCase):

    def setUp(self) -> None:
        self.client = MT5Client()

    @patch('MetaTrader5.initialize')
    @patch('MetaTrader5.account_info')
    def test_initialize_success(self, mock_account, mock_init) -> None:
        mock_init.return_value = True
        mock_account.return_value = SimpleNamespace(
            login=123456,
            server="DemoServer",
            currency="USD",
            balance=10000.0
        )

        success = self.client.initialize(login=123456, password="secretpassword", server="DemoServer")
        self.assertTrue(success)
        self.assertTrue(self.client.is_connected)

    @patch('MetaTrader5.initialize')
    @patch('MetaTrader5.last_error')
    def test_initialize_failure(self, mock_last_error, mock_init) -> None:
        mock_init.return_value = False
        mock_last_error.return_value = (-1, "Terminal not found")

        success = self.client.initialize()
        self.assertFalse(success)
        self.assertFalse(self.client.is_connected)

    @patch('MetaTrader5.copy_rates_from_pos')
    @patch('MetaTrader5.terminal_info')
    def test_copy_rates_from_pos(self, mock_term, mock_rates) -> None:
        mock_term.return_value = SimpleNamespace(connected=True)
        self.client._connected = True

        # Mock structured array returned by mt5.copy_rates_from_pos
        dtype = [('time', 'i8'), ('open', 'f8'), ('high', 'f8'), ('low', 'f8'), ('close', 'f8'), ('tick_volume', 'i8'), ('spread', 'i4'), ('real_volume', 'i8')]
        rates_data = np.array([
            (1672531200, 1.1000, 1.1050, 1.0950, 1.1020, 100, 1, 0),
            (1672531500, 1.1020, 1.1060, 1.1010, 1.1040, 120, 1, 0)
        ], dtype=dtype)

        mock_rates.return_value = rates_data

        df = self.client.copy_rates_from_pos('EURUSD', 5, 0, 2)
        self.assertEqual(len(df), 2)
        self.assertIn('close', df.columns)
        self.assertIn('time', df.columns)

    @patch('MetaTrader5.order_send')
    @patch('MetaTrader5.terminal_info')
    def test_order_send(self, mock_term, mock_order) -> None:
        mock_term.return_value = SimpleNamespace(connected=True)
        self.client._connected = True

        mock_result = SimpleNamespace(
            retcode=10009,  # TRADE_RETCODE_DONE
            deal=999111,
            order=888222,
            price=1.1020,
            volume=0.1
        )
        mock_order.return_value = mock_result

        request = {"action": 1, "symbol": "EURUSD", "volume": 0.1, "type": 0, "price": 1.1020}
        res = self.client.order_send(request)
        self.assertIsNotNone(res)
        self.assertEqual(res.retcode, 10009)
