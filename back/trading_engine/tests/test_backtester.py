import json
from django.test import TestCase, Client
from django.urls import reverse
from trading_engine.backtester import BacktestEngine


class BacktestEngineTestCase(TestCase):
    """
    Test suite for BacktestEngine bar-by-bar simulation and metrics calculation.
    """

    def setUp(self):
        self.client = Client()
        self.algo_config = {
            "name": "Test Strategy",
            "operator": "WEIGHTED",
            "threshold": 0.5,
            "indicators": [
                {
                    "id": "rsi",
                    "name": "RSI Indicator",
                    "timeframe": "M5",
                    "params": {"period": 14},
                    "weight": 0.5
                },
                {
                    "id": "macd",
                    "name": "MACD Z-Score",
                    "timeframe": "M5",
                    "params": {"fast": 12, "slow": 26, "signal": 9, "z_window": 100},
                    "weight": 0.5
                }
            ]
        }
        self.buy_in_config = {
            "method": "Simple Buy-in",
            "risk_percentage": 1.0,
            "sl_tp_ratio": 2.0,
            "max_active_positions": 1
        }

    def test_backtest_engine_run(self):
        engine = BacktestEngine()
        report = engine.run(
            algorithm_config=self.algo_config,
            buy_in_config=self.buy_in_config,
            symbol="EURUSD",
            date_from="2026-01-01",
            date_to="2026-03-01",
            initial_balance=10000.0,
            timeframe=5
        )

        self.assertIn("symbol", report)
        self.assertEqual(report["symbol"], "EURUSD")
        self.assertEqual(report["initial_balance"], 10000.0)
        self.assertIn("final_balance", report)
        self.assertIn("win_rate", report)
        self.assertIn("total_net_profit", report)
        self.assertIn("equity_curve", report)
        self.assertIn("trades", report)
        self.assertTrue(isinstance(report["equity_curve"], list))
        self.assertTrue(isinstance(report["trades"], list))

    def test_backtest_endpoint_post(self):
        payload = {
            "algorithm_config": self.algo_config,
            "buy_in_config": self.buy_in_config,
            "symbol": "EURUSD",
            "date_from": "2026-01-01",
            "date_to": "2026-03-01",
            "initial_balance": 10000.0,
            "timeframe": 5
        }

        response = self.client.post(
            reverse('backtest'),
            data=json.dumps(payload),
            content_type='application/json'
        )

        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content.decode('utf-8'))
        self.assertEqual(data["status"], "success")
        self.assertIn("report", data)
        self.assertEqual(data["report"]["symbol"], "EURUSD")
