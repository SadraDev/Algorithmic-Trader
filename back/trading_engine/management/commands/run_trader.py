import time
import logging
from django.core.management.base import BaseCommand
from trading_engine.executor import execute_trading_cycle
from trading_engine.models import StrategyConfig

logger = logging.getLogger('trading_engine')


class Command(BaseCommand):
    help = 'Executes the MetaTrader 5 algorithmic trading engine.'

    def add_arguments(self, parser):
        parser.add_argument('--symbol', type=str, default=None, help='Symbol to trade (e.g., EURUSD)')
        parser.add_argument('--timeframe', type=int, default=None, help='Timeframe in minutes (e.g., 5 for M5)')
        parser.add_argument('--risk', type=float, default=None, help='Risk percentage per trade')
        parser.add_argument('--ratio', type=float, default=2.0, help='Take-profit to stop-loss ratio')
        parser.add_argument('--operator', type=str, default='OR', choices=['AND', 'OR'], help='Combiner logical operator')
        parser.add_argument('--loop', action='store_true', help='Run continuously in a loop')
        parser.add_argument('--interval', type=int, default=10, help='Loop interval in seconds (default 10s)')

    def handle(self, *args, **options):
        symbol = options['symbol']
        timeframe = options['timeframe']
        risk = options['risk']
        ratio = options['ratio']
        operator = options['operator']
        loop = options['loop']
        interval = options['interval']

        self.stdout.write(self.style.SUCCESS("=== MT5 Algorithmic Trading Engine Started ==="))

        # Load active strategy config if parameters not explicitly provided
        if symbol is None or timeframe is None:
            active_config = StrategyConfig.objects.filter(is_active=True).first()
            if active_config:
                symbol = symbol or active_config.symbol
                timeframe = timeframe or active_config.timeframe
                risk = risk if risk is not None else active_config.risk_percentage
                ratio = ratio if ratio is not None else active_config.sl_tp_ratio
                operator = operator or active_config.operator

        symbol = symbol or "EURUSD"
        timeframe = timeframe or 5
        risk = risk if risk is not None else 1.0
        ratio = ratio if ratio is not None else 2.0
        operator = operator or "OR"

        self.stdout.write(
            f"Configured Strategy: Symbol={symbol}, Timeframe=M{timeframe}, "
            f"Risk={risk}%, R:R Ratio={ratio}, Operator={operator}"
        )

        def run_once():
            self.stdout.write(f"Running trading cycle for {symbol}...")
            summary = execute_trading_cycle(
                symbol=symbol,
                timeframe=timeframe,
                risk_percentage=risk,
                sl_tp_ratio=ratio,
                operator=operator
            )
            self.stdout.write(self.style.NOTICE(f"Cycle result: {summary}"))

        if loop:
            self.stdout.write(self.style.WARNING(f"Entering continuous loop (interval: {interval}s). Press Ctrl+C to stop."))
            try:
                while True:
                    run_once()
                    time.sleep(interval)
            except KeyboardInterrupt:
                self.stdout.write(self.style.SUCCESS("Trading Engine loop stopped gracefully."))
        else:
            run_once()
