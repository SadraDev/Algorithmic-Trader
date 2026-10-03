from .infrastructure.mt5.executor import (
    IndicatorAdapter,
    TradingExecutor,
    InstanceWorker,
    InstanceManager,
)

def run_execution_cycle(
    symbol: str = "EURUSD",
    timeframe: int = 5,
    risk_percentage: float = 1.0,
    sl_tp_ratio: float = 2.0,
    signal_threshold: float = 0.5,
    max_active_positions: int = 1
):
    executor = TradingExecutor(
        symbol=symbol,
        timeframe=timeframe,
        risk_percentage=risk_percentage,
        sl_tp_ratio=sl_tp_ratio,
        signal_threshold=signal_threshold,
        max_active_positions=max_active_positions
    )
    return executor.run_execution_cycle()

execute_trading_cycle = run_execution_cycle

__all__ = [
    "IndicatorAdapter",
    "TradingExecutor",
    "InstanceWorker",
    "InstanceManager",
    "run_execution_cycle",
    "execute_trading_cycle",
]
