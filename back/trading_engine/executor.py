"""
Execution Engine Module.
Coordinates MT5 client data retrieval, signal evaluation via AlgorithmCombiner,
trade trigger validation & risk calculation via OpenStrategy, order execution,
open position management via CloseStrategy, and multi-instance background workers.
"""

import logging
import threading
import time
import uuid
from typing import Optional, Dict, Any, List
import pandas as pd
import MetaTrader5 as mt5

from .mt5_client import MT5Client
from .algorithms import AlgorithmCombiner, MACDCrossover, RSIOversold, BaseAlgorithm
from .indicators import RSIIndicator, StochasticIndicator, MACDIndicator, BollingerBandsIndicator
from .strategies import OpenStrategy, CloseStrategy

logger = logging.getLogger(__name__)


class IndicatorAdapter(BaseAlgorithm):
    """
    Adapts a BaseIndicator (which returns pd.Series) to BaseAlgorithm (which evaluates latest bar signal).
    """

    def __init__(self, indicator: Any) -> None:
        self.indicator = indicator

    def evaluate(self, dataframe: pd.DataFrame) -> float:
        series = self.indicator.evaluate(dataframe)
        if series is None or series.empty:
            return 0.0
        return float(series.iloc[-1])


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

        # Default combiner setup if none provided
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
        """
        Runs a complete execution cycle for the configured symbol.
        """
        summary: Dict[str, Any] = {
            "symbol": self.symbol,
            "signal": 0,
            "trigger_valid": False,
            "order_executed": False,
            "closed_positions_count": 0,
            "errors": []
        }

        logger.info("--- Starting Trading Engine Execution Cycle [%s] ---", self.symbol)

        # 1. Fetch latest rates via MT5 Client
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

        # 2. Evaluate consolidated score and signal from AlgorithmCombiner
        score = float(self.combiner.calculate_composite_score(dataframe))
        signal = int(self.combiner.evaluate(dataframe))
        summary["score"] = score
        summary["signal"] = signal
        logger.info("AlgorithmCombiner generated score: %.4f, signal: %d for %s", score, signal, self.symbol)

        # 3. If threshold is breached, verify active position count before firing order
        if signal in (1, -1):
            summary["trigger_valid"] = True

            active_positions = self.client.positions_get(symbol=self.symbol)
            open_count = len(active_positions) if active_positions else 0

            if open_count >= self.open_strategy.max_active_positions:
                err_msg = f"Order suppressed: Max active positions cap reached for {self.symbol} ({open_count}/{self.open_strategy.max_active_positions})"
                logger.info(err_msg)
                summary["errors"].append(err_msg)
            else:
                order_result = self._execute_open_trade(signal, dataframe)
                if order_result is not None:
                    retcode = getattr(order_result, 'retcode', None)
                    done_code = getattr(mt5, 'TRADE_RETCODE_DONE', 10009)
                    placed_code = getattr(mt5, 'TRADE_RETCODE_PLACED', 10008)

                    if retcode in (done_code, placed_code, None) or getattr(order_result, 'deal', 0) > 0:
                        summary["order_executed"] = True
                        summary["order_result"] = {
                            "deal": getattr(order_result, 'deal', 0),
                            "order": getattr(order_result, 'order', 0),
                            "price": getattr(order_result, 'price', 0.0),
                            "volume": getattr(order_result, 'volume', 0.0)
                        }
                    else:
                        err_msg = f"MT5 order send retcode: {retcode} - {getattr(order_result, 'comment', '')}"
                        logger.error(err_msg)
                        summary["errors"].append(err_msg)

        # 4. Iterate over open positions and evaluate CloseStrategy
        closed_count = self._manage_open_positions(dataframe)
        summary["closed_positions_count"] = closed_count

        logger.info("--- Execution Cycle Complete [%s]. Summary: %s ---", self.symbol, summary)
        return summary

    def _execute_open_trade(self, signal: int, dataframe: pd.DataFrame) -> Optional[Any]:
        """
        Calculates SL, TP, and position size, and sends order request via MT5 Client.
        """
        tick = self.client.symbol_info_tick(self.symbol)
        if tick is None:
            logger.error("Cannot execute trade: Symbol tick data unavailable for %s", self.symbol)
            return None

        sym_info = self.client.symbol_info(self.symbol)
        acc_info = self.client.account_info()
        balance = getattr(acc_info, 'balance', 10000.0) if acc_info else 10000.0

        # Determine entry price and order type
        if signal == 1:
            entry_price = tick.ask
            order_type = getattr(mt5, 'ORDER_TYPE_BUY', 0)
        else:
            entry_price = tick.bid
            order_type = getattr(mt5, 'ORDER_TYPE_SELL', 1)

        sl_price, tp_price = self.open_strategy.calculate_sl_tp(
            signal=signal,
            entry_price=entry_price,
            dataframe=dataframe,
            sl_tp_ratio=self.sl_tp_ratio
        )

        volume = self.open_strategy.calculate_position_size(
            account_balance=balance,
            risk_percentage=self.risk_percentage,
            entry_price=entry_price,
            sl_price=sl_price,
            symbol_info=sym_info
        )

        # Determine supported filling mode based on symbol_info capability
        filling_type = getattr(mt5, 'ORDER_FILLING_IOC', 1)
        if sym_info is not None:
            filling_mode = getattr(sym_info, 'filling_mode', 0)
            if filling_mode & 1:  # SYMBOL_FILLING_FOK
                filling_type = getattr(mt5, 'ORDER_FILLING_FOK', 0)
            elif filling_mode & 2:  # SYMBOL_FILLING_IOC
                filling_type = getattr(mt5, 'ORDER_FILLING_IOC', 1)
            elif filling_mode & 4:  # SYMBOL_FILLING_RETURN
                filling_type = getattr(mt5, 'ORDER_FILLING_RETURN', 2)

        # Prepare order request payload
        request = {
            "action": getattr(mt5, 'TRADE_ACTION_DEAL', 1),
            "symbol": self.symbol,
            "volume": volume,
            "type": order_type,
            "price": entry_price,
            "sl": sl_price,
            "tp": tp_price,
            "deviation": 20,
            "magic": 999888,
            "comment": "trading_engine auto trade",
            "type_time": getattr(mt5, 'ORDER_TIME_GTC', 0),
            "type_filling": filling_type,
        }

        logger.info(
            "Executing %s order for %s: Vol=%.2f, Price=%.5f, SL=%.5f, TP=%.5f, Filling=%d",
            "BUY" if signal == 1 else "SELL",
            self.symbol,
            volume,
            entry_price,
            sl_price,
            tp_price,
            filling_type
        )

        return self.client.order_send(request)

    def _manage_open_positions(self, dataframe: pd.DataFrame) -> int:
        """
        Fetches currently open positions for symbol and evaluates CloseStrategy early exits.
        """
        positions = self.client.positions_get(symbol=self.symbol)
        if not positions:
            return 0

        closed_count = 0
        for pos in positions:
            should_close = self.close_strategy.evaluate_position(pos, dataframe)
            if should_close:
                logger.info("CloseStrategy triggered early exit for position #%s on %s",
                            getattr(pos, 'ticket', 'N/A'), self.symbol)
                result = self.client.close_position(pos)
                if result is not None and getattr(result, 'retcode', None) == getattr(mt5, 'TRADE_RETCODE_DONE', 10009):
                    closed_count += 1

        return closed_count


def execute_trading_cycle(
    symbol: str = "EURUSD",
    timeframe: int = 5,
    risk_percentage: float = 1.0,
    sl_tp_ratio: float = 2.0,
    operator: str = "WEIGHTED",
    signal_threshold: float = 0.5,
    max_active_positions: int = 1,
    indicators: Optional[List[Dict[str, Any]]] = None
) -> Dict[str, Any]:
    """
    Convenience function to instantiate and run a single trading cycle.
    """
    algorithm_instances = []
    weights_list = []

    if indicators:
        for ind_item in indicators:
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
        algorithm_instances = [
            MACDCrossover(12, 26, 9),
            RSIOversold(14, 30.0, 70.0)
        ]
        weights_list = [0.5, 0.5]

    combiner = AlgorithmCombiner(
        algorithms=algorithm_instances,
        weights=weights_list,
        operator=operator,  # type: ignore
        signal_threshold=signal_threshold
    )

    executor = TradingExecutor(
        symbol=symbol,
        timeframe=timeframe,
        risk_percentage=risk_percentage,
        sl_tp_ratio=sl_tp_ratio,
        signal_threshold=signal_threshold,
        max_active_positions=max_active_positions,
        combiner=combiner
    )

    return executor.run_execution_cycle()


class InstanceWorker(threading.Thread):
    """
    Background worker thread evaluating a single algorithm deployment continuously.
    """

    def __init__(
        self,
        instance_id: str,
        name: str,
        symbol: str,
        timeframe: int,
        risk_percentage: float,
        sl_tp_ratio: float,
        operator: str,
        signal_threshold: float,
        max_active_positions: int = 1,
        indicators: Optional[List[Dict[str, Any]]] = None
    ) -> None:
        super().__init__(daemon=True)
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

        self.status = "RUNNING"  # RUNNING, PAUSED, TRIGGERED, STOPPED
        self.latest_score = 0.0
        self.latest_bias = "NEUTRAL (0.00)"
        self.last_run_time = ""
        self.stop_event = threading.Event()
        self.pause_event = threading.Event()

    def run(self) -> None:
        logger.info("Starting background InstanceWorker [%s] on %s (M%d)...", self.name, self.symbol, self.timeframe)
        while not self.stop_event.is_set():
            if self.pause_event.is_set():
                self.status = "PAUSED"
                time.sleep(2)
                continue

            self.status = "RUNNING"
            try:
                summary = execute_trading_cycle(
                    symbol=self.symbol,
                    timeframe=self.timeframe,
                    risk_percentage=self.risk_percentage,
                    sl_tp_ratio=self.sl_tp_ratio,
                    operator=self.operator,
                    signal_threshold=self.signal_threshold,
                    max_active_positions=self.max_active_positions,
                    indicators=self.indicators
                )

                score = float(summary.get("score", 0.0))
                signal = summary.get("signal", 0)

                self.latest_score = score
                self.latest_bias = f"BULLISH (+{score:.2f})" if score > 0.2 else (f"BEARISH ({score:.2f})" if score < -0.2 else f"NEUTRAL ({score:.2f})")

                if summary.get("order_executed", False):
                    self.status = "TRIGGERED"

                import datetime
                self.last_run_time = datetime.datetime.now().strftime('%H:%M:%S')

            except Exception as e:
                logger.error("Error in InstanceWorker [%s]: %s", self.name, e)

            # Continuous Polling Loop: 5s
            time.sleep(5)

        self.status = "STOPPED"

    def pause(self) -> None:
        if self.pause_event.is_set():
            self.pause_event.clear()
            self.status = "RUNNING"
        else:
            self.pause_event.set()
            self.status = "PAUSED"

    def stop(self) -> None:
        self.stop_event.set()
        self.status = "STOPPED"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "instance_id": self.instance_id,
            "name": self.name,
            "symbol": self.symbol,
            "timeframe": self.timeframe,
            "risk_percentage": self.risk_percentage,
            "sl_tp_ratio": self.sl_tp_ratio,
            "operator": self.operator,
            "signal_threshold": self.signal_threshold,
            "max_active_positions": self.max_active_positions,
            "status": self.status,
            "latest_score": round(self.latest_score, 4),
            "latest_bias": self.latest_bias,
            "last_run_time": self.last_run_time,
        }


class InstanceManager:
    """
    Singleton manager tracking all continuous background algorithm deployments.
    """
    _instance: Optional['InstanceManager'] = None
    _lock = threading.Lock()

    def __new__(cls) -> 'InstanceManager':
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super(InstanceManager, cls).__new__(cls)
                    cls._instance.workers: Dict[str, InstanceWorker] = {}
        return cls._instance

    def start_instance(
        self,
        name: str,
        symbol: str = "EURUSD",
        timeframe: int = 5,
        risk_percentage: float = 1.0,
        sl_tp_ratio: float = 2.0,
        operator: str = "WEIGHTED",
        signal_threshold: float = 0.5,
        max_active_positions: int = 1,
        indicators: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        instance_id = str(uuid.uuid4())[:8]
        worker = InstanceWorker(
            instance_id=instance_id,
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
        with self._lock:
            self.workers[instance_id] = worker
        worker.start()
        return worker.to_dict()

    def list_instances(self) -> List[Dict[str, Any]]:
        with self._lock:
            return [w.to_dict() for w in self.workers.values() if w.status != "STOPPED"]

    def pause_instance(self, instance_id: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            worker = self.workers.get(instance_id)
            if worker:
                worker.pause()
                return worker.to_dict()
        return None

    def stop_instance(self, instance_id: str) -> bool:
        with self._lock:
            worker = self.workers.get(instance_id)
            if worker:
                worker.stop()
                del self.workers[instance_id]
                return True
        return False
