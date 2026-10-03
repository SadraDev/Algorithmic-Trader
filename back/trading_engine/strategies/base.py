from abc import ABC, abstractmethod
import logging
import math
from typing import Optional, Any, Dict
import pandas as pd

logger = logging.getLogger(__name__)


class BaseBuyInStrategy(ABC):
    """
    Abstract Base Class for all Buy-in strategies.
    Encapsulates SL, TP, lot volume sizing, and exit conditions.
    """

    def __init__(
        self,
        risk_percentage: float = 1.0,
        sl_tp_ratio: float = 2.0,
        max_active_positions: int = 1,
        **kwargs: Any
    ) -> None:
        if risk_percentage <= 0 or risk_percentage > 100:
            raise ValueError("risk_percentage must be between 0 and 100")
        if sl_tp_ratio <= 0:
            raise ValueError("sl_tp_ratio must be greater than 0")

        self.risk_percentage = float(risk_percentage)
        self.sl_tp_ratio = float(sl_tp_ratio)
        self.max_active_positions = max(1, int(max_active_positions))

    @abstractmethod
    def calculate_trade_parameters(
        self,
        signal: int,
        entry_price: float,
        dataframe: pd.DataFrame,
        account_balance: float,
        symbol_info: Optional[Any] = None
    ) -> Dict[str, Any]:
        """
        Calculates SL, TP, and lot volume for a new trade entry.

        :return: Dict containing 'sl_price', 'tp_price', 'volume'
        """
        pass

    @abstractmethod
    def evaluate_exit(
        self,
        position: Any,
        dataframe: pd.DataFrame
    ) -> Optional[Dict[str, Any]]:
        """
        Evaluates active position for strategy-specific exit conditions.

        :return: None if no exit, or Dict with 'should_close', 'exit_price', 'exit_reason'
        """
        pass

    def _calculate_lot_volume(
        self,
        account_balance: float,
        risk_percentage: float,
        entry_price: float,
        sl_price: float,
        symbol_info: Optional[Any] = None
    ) -> float:
        """
        Calculates position volume (lots) according to account balance, risk percentage, and distance to SL.
        """
        if account_balance <= 0 or risk_percentage <= 0:
            return 0.01

        risk_amount = account_balance * (risk_percentage / 100.0)
        price_distance = abs(entry_price - sl_price)

        if price_distance <= 0:
            logger.warning("Price distance between entry and SL is zero or negative. Using default lot 0.01.")
            return 0.01

        if symbol_info is not None:
            tick_size = getattr(symbol_info, 'trade_tick_size', getattr(symbol_info, 'point', 0.00001))
            tick_value = getattr(symbol_info, 'trade_tick_value', None)
            volume_min = getattr(symbol_info, 'volume_min', 0.01)
            volume_max = getattr(symbol_info, 'volume_max', 100.0)
            volume_step = getattr(symbol_info, 'volume_step', 0.01)

            if tick_size > 0 and tick_value is not None and tick_value > 0:
                ticks_at_risk = price_distance / tick_size
                loss_per_lot = ticks_at_risk * tick_value
                raw_lots = (risk_amount / loss_per_lot) if loss_per_lot > 0 else 0.01
            else:
                contract_size = getattr(symbol_info, 'trade_contract_size', 100000.0)
                raw_lots = risk_amount / (price_distance * contract_size)
        else:
            volume_min, volume_max, volume_step = 0.01, 100.0, 0.01
            raw_lots = risk_amount / (price_distance * 100000.0)

        steps = math.floor(raw_lots / volume_step) if volume_step > 0 else 1
        calculated_lots = steps * volume_step if steps > 0 else volume_min

        final_lots = max(volume_min, min(volume_max, calculated_lots))
        return round(final_lots, 2)
