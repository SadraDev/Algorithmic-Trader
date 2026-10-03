import logging
import threading
import time
import uuid
from typing import Optional, Dict, Any, List
import pandas as pd
import MetaTrader5 as mt5

from .mt5_client import MT5Client
from ...algorithms import AlgorithmCombiner, MACDCrossover, RSIOversold, BaseAlgorithm
from ...strategies import OpenStrategy, CloseStrategy

logger = logging.getLogger(__name__)


class IndicatorAdapter(BaseAlgorithm):
    """
    Adapts an Indicator to BaseAlgorithm evaluating the latest bar signal.
    """

    def __init__(self, indicator: Any) -> None:
        self.indicator = indicator

    def evaluate(self, dataframe: pd.DataFrame) -> float:
        val = self.indicator.evaluate(dataframe)
        if val is None:
            return 0.0
        if isinstance(val, (int, float)):
            return float(val)
        if hasattr(val, 'empty') and not val.empty:
            return float(val.iloc[-1])
        return 0.0


class TradingExecutor:
    """
    Master Trading Executor orchestrating data fetching, algorithm evaluation,
    order placement, and position early exits.
    """

    def __init__(
        self,
        symbol: str = "EURUSD",
        timeframe: int = mt5.TIMEFRAME_M5 if hasattr(mt5, 'TIMEFRAME_M5') else 5,
        risk_percentage: float = 1.0,
        sl_tp_ratio: float = 2.0,
        signal_threshold: float = 0.5,
        max_active_positions: int = 1,
        combiner: Optional[AlgorithmCombiner] = None,
        open_strategy: Optional[OpenStrategy] = None,
        close_strategy: Optional[CloseStrategy] = None,
        client: Optional[MT5Client] = None
    ) -> None:
        self.symbol = symbol
        self.timeframe = timeframe
        self.risk_percentage = risk_percentage
        self.sl_tp_ratio = sl_tp_ratio
        self.signal_threshold = signal_threshold

        if combiner is None:
            self.combiner = AlgorithmCombiner(
                algorithms=[
                    MACDCrossover(fast_period=12, slow_period=26, signal_period=9),
                    RSIOversold(period=14, oversold=30.0, overbought=70.0)
                ],
                operator='OR',
                signal_threshold=signal_threshold
            )
        else:
            self.combiner = combiner

        self.open_strategy = open_strategy or OpenStrategy(
            risk_percentage=risk_percentage,
            sl_tp_ratio=sl_tp_ratio,
            max_active_positions=max_active_positions
        )
        self.close_strategy = close_strategy or CloseStrategy(choch_window=5)
        self.client = client or MT5Client()

    def run_execution_cycle(self, candle_count: int = 100) -> Dict[str, Any]:
        summary: Dict[str, Any] = {
            "symbol": self.symbol,
            "signal": 0,
            "trigger_valid": False,
            "order_executed": False,
            "closed_positions_count": 0,
            "errors": []
        }

        logger.info("--- Starting Trading Engine Execution Cycle [%s] ---", self.symbol)

        try:
            dataframe = self.client.copy_rates_from_pos(self.symbol, self.timeframe, start_pos=0, count=candle_count)
        except Exception as e:
            err_msg = f"Failed to fetch rates for {self.symbol}: {e}"
            logger.error(err_msg)
            summary["errors"].append(err_msg)
            return summary

        if dataframe is None or dataframe.empty or len(dataframe) < 30:
            err_msg = f"Insufficient rate data retrieved for {self.symbol} (rows: {len(dataframe) if dataframe is not None else 0})"
            logger.warning(err_msg)
            summary["errors"].append(err_msg)
            return summary

        score = float(self.combiner.calculate_composite_score(dataframe))
        signal = int(self.combiner.evaluate(dataframe))
        summary["score"] = score
        summary["signal"] = signal
        logger.info("AlgorithmCombiner generated score: %.4f, signal: %d for %s", score, signal, self.symbol)

        open_positions = self.client.get_positions(symbol=self.symbol)
        active_position_count = len(open_positions)

        for pos in open_positions:
            should_close = self.close_strategy.evaluate_position(position=pos, dataframe=dataframe)
            if should_close:
                close_res = self.client.close_position(position_id=pos["ticket"])
                if close_res.get("success"):
                    summary["closed_positions_count"] += 1
                    logger.info("Successfully closed position #%d for %s via CloseStrategy.", pos["ticket"], self.symbol)
                else:
                    err_msg = f"Failed to close position #{pos['ticket']}: {close_res.get('error')}"
                    logger.error(err_msg)
                    summary["errors"].append(err_msg)

        if active_position_count >= self.open_strategy.max_active_positions:
            logger.info("Max active positions limit reached (%d/%d) for %s. Skipping order entry.",
                        active_position_count, self.open_strategy.max_active_positions, self.symbol)
            return summary

        if signal in (1, -1):
            is_valid = self.open_strategy.validate_trigger(signal=signal, dataframe=dataframe)
            summary["trigger_valid"] = is_valid

            if is_valid:
                entry_price = float(dataframe.iloc[-1]["close"])
                sl_price, tp_price = self.open_strategy.calculate_sl_tp(
                    signal=signal,
                    entry_price=entry_price,
                    dataframe=dataframe,
                    sl_tp_ratio=self.sl_tp_ratio
                )

                account_info = self.client.get_account_info()
                account_balance = account_info["balance"] if account_info else 10000.0
                symbol_info = self.client.get_symbol_info(self.symbol)

                volume = self.open_strategy.calculate_position_size(
                    account_balance=account_balance,
                    risk_percentage=self.risk_percentage,
                    entry_price=entry_price,
                    sl_price=sl_price,
                    symbol_info=symbol_info
                )

                order_type = "BUY" if signal == 1 else "SELL"
                logger.info("Executing %s order for %s: Vol=%.2f, Price=%.5f, SL=%.5f, TP=%.5f, Filling=1",
                            order_type, self.symbol, volume, entry_price, sl_price, tp_price)

                order_result = self.client.place_market_order(
                    symbol=self.symbol,
                    order_type=order_type,
                    volume=volume,
                    sl=sl_price,
                    tp=tp_price,
                    comment="AlgorithmicTrader Entry"
                )

                summary["order_executed"] = order_result.get("success", False)
                summary["order_result"] = order_result
            else:
                logger.info("Signal %d generated but trigger validation failed for %s.", signal, self.symbol)

        logger.info("--- Execution Cycle Complete [%s]. Summary: %s ---", self.symbol, summary)
        return summary


def run_execution_cycle(
    symbol: str = "EURUSD",
    timeframe: int = 5,
    risk_percentage: float = 1.0,
    sl_tp_ratio: float = 2.0,
    signal_threshold: float = 0.5,
    max_active_positions: int = 1
) -> Dict[str, Any]:
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


class InstanceWorker:
    def __init__(
        self,
        instance_id: str,
        name: str,
        symbol: str = "EURUSD",
        timeframe: int = 5,
        risk_percentage: float = 1.0,
        sl_tp_ratio: float = 2.0,
        operator: str = "WEIGHTED",
        signal_threshold: float = 0.5,
        max_active_positions: int = 1,
        indicators: Optional[List[Dict[str, Any]]] = None,
        poll_interval: int = 5
    ) -> None:
        self.instance_id = instance_id
        self.name = name
        self.symbol = symbol
        self.timeframe = timeframe
        self.risk_percentage = risk_percentage
        self.sl_tp_ratio = sl_tp_ratio
        self.operator = operator
        self.signal_threshold = signal_threshold
        self.max_active_positions = max_active_positions
        self.indicators = indicators or []
        self.poll_interval = poll_interval

        self.latest_score = 0.0
        self.status = "INITIALIZING"
        self._running = False
        self._thread: Optional[threading.Thread] = None

        combiner = self._build_combiner()
        self.executor = TradingExecutor(
            symbol=symbol,
            timeframe=timeframe,
            risk_percentage=risk_percentage,
            sl_tp_ratio=sl_tp_ratio,
            signal_threshold=signal_threshold,
            max_active_positions=max_active_positions,
            combiner=combiner
        )

    def _build_combiner(self) -> AlgorithmCombiner:
        from ...algorithms import RSIIndicator, StochasticIndicator, MACDIndicator, BollingerBandsIndicator
        algorithm_instances = []
        weights_list = []

        if self.indicators:
            for ind_item in self.indicators:
                ind_id = ind_item.get("id", "rsi")
                params = ind_item.get("params", {})
                w = float(ind_item.get("weight", 0.5))

                if ind_id == "rsi":
                    obj = RSIIndicator(period=int(params.get("period", 14)))
                elif ind_id == "stochastic":
                    obj = StochasticIndicator(
                        k_period=int(params.get("k_period", 14)),
                        d_period=int(params.get("d_period", 3))
                    )
                elif ind_id == "macd":
                    obj = MACDIndicator(
                        fast=int(params.get("fast", 12)),
                        slow=int(params.get("slow", 26)),
                        signal=int(params.get("signal", 9)),
                        z_window=int(params.get("z_window", 100))
                    )
                elif ind_id == "bollinger":
                    obj = BollingerBandsIndicator(
                        period=int(params.get("period", 20)),
                        std_dev=float(params.get("std_dev", 2.0))
                    )
                else:
                    continue

                algorithm_instances.append(IndicatorAdapter(obj))
                weights_list.append(w)

        if not algorithm_instances:
            algorithm_instances = [MACDCrossover(12, 26, 9), RSIOversold(14, 30.0, 70.0)]
            weights_list = [0.5, 0.5]

        return AlgorithmCombiner(
            algorithms=algorithm_instances,
            weights=weights_list,
            operator=self.operator,  # type: ignore
            signal_threshold=self.signal_threshold
        )

    def start(self) -> None:
        if self._running:
            return
        self._running = True
        self.status = "RUNNING"
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        logger.info("Background Worker Thread started for Instance [%s] (%s)", self.instance_id, self.symbol)

    def stop(self) -> None:
        self._running = False
        self.status = "STOPPED"
        logger.info("Stopping Worker Thread for Instance [%s] (%s)...", self.instance_id, self.symbol)

    def _run(self) -> None:
        while self._running:
            try:
                summary = self.executor.run_execution_cycle()
                self.latest_score = summary.get("score", 0.0)
            except Exception as e:
                logger.error("Error in background worker [%s]: %s", self.instance_id, e)

            for _ in range(self.poll_interval):
                if not self._running:
                    break
                time.sleep(1)


class InstanceManager:
    _instance: Optional['InstanceManager'] = None
    _lock: threading.Lock = threading.Lock()

    def __new__(cls) -> 'InstanceManager':
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super(InstanceManager, cls).__new__(cls)
                    cls._instance.workers = {}
        return cls._instance

    def create_and_start_instance(
        self,
        name: str,
        symbol: str = "EURUSD",
        timeframe: int = 5,
        risk_percentage: float = 1.0,
        sl_tp_ratio: float = 2.0,
        operator: str = "WEIGHTED",
        signal_threshold: float = 0.5,
        max_active_positions: int = 1,
        indicators: Optional[List[Dict[str, Any]]] = None,
        instance_id: Optional[str] = None
    ) -> InstanceWorker:
        id_str = instance_id or str(uuid.uuid4())[:8]
        worker = InstanceWorker(
            instance_id=id_str,
            name=name,
            symbol=symbol,
            timeframe=timeframe,
            risk_percentage=risk_percentage,
            sl_tp_ratio=sl_tp_ratio,
            operator=operator,
            signal_threshold=signal_threshold,
            max_active_positions=max_active_positions,
            indicators=indicators
        )
        self.workers[id_str] = worker
        worker.start()
        return worker

    def stop_instance(self, instance_id: str) -> bool:
        if instance_id in self.workers:
            self.workers[instance_id].stop()
            del self.workers[instance_id]
            return True
        return False

    def get_instance_status(self, instance_id: str) -> Optional[Dict[str, Any]]:
        w = self.workers.get(instance_id)
        if not w:
            return None
        return {
            "instance_id": w.instance_id,
            "name": w.name,
            "symbol": w.symbol,
            "timeframe": w.timeframe,
            "status": w.status,
            "latest_score": w.latest_score,
            "risk_percentage": w.risk_percentage,
            "sl_tp_ratio": w.sl_tp_ratio,
            "max_active_positions": w.max_active_positions,
        }

    def list_all_instances(self) -> List[Dict[str, Any]]:
        return [self.get_instance_status(i) for i in self.workers]
