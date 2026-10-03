from typing import Optional, Any, Dict
import pandas as pd

from .base import BaseBuyInStrategy
from .compat import CloseStrategy


class SwingExtremaBuyInStrategy(BaseBuyInStrategy):
    """
    Market Structure Swing Extrema Buy-in Strategy.
    Calculates SL using recent local swing extrema (low/high) and projects TP via ratio.
    Optionally evaluates Change of Character (CHoCH) early exits.
    """

    def __init__(
        self,
        risk_percentage: float = 1.0,
        sl_tp_ratio: float = 2.0,
        max_active_positions: int = 1,
        swing_lookback: int = 15,
        enable_choch_exit: bool = True,
        **kwargs: Any
    ) -> None:
        super().__init__(risk_percentage, sl_tp_ratio, max_active_positions)
        self.swing_lookback = swing_lookback
        self.enable_choch_exit = enable_choch_exit
        self.close_strategy = CloseStrategy(choch_window=5) if enable_choch_exit else None

    def calculate_trade_parameters(
        self,
        signal: int,
        entry_price: float,
        dataframe: pd.DataFrame,
        account_balance: float,
        symbol_info: Optional[Any] = None
    ) -> Dict[str, Any]:
        if dataframe is None or len(dataframe) < 2:
            default_offset = entry_price * 0.005
            if signal == 1:
                sl_price = entry_price - default_offset
                tp_price = entry_price + (default_offset * self.sl_tp_ratio)
            else:
                sl_price = entry_price + default_offset
                tp_price = entry_price - (default_offset * self.sl_tp_ratio)
        else:
            recent_df = dataframe.tail(min(self.swing_lookback, len(dataframe)))

            if signal == 1:
                lowest_low = float(recent_df['low'].min())
                buffer = max((entry_price - lowest_low) * 0.05, entry_price * 0.0003)
                sl_price = lowest_low - buffer
                if sl_price >= entry_price:
                    sl_price = entry_price * 0.995
                risk = entry_price - sl_price
                tp_price = entry_price + (risk * self.sl_tp_ratio)

            elif signal == -1:
                highest_high = float(recent_df['high'].max())
                buffer = max((highest_high - entry_price) * 0.05, entry_price * 0.0003)
                sl_price = highest_high + buffer
                if sl_price <= entry_price:
                    sl_price = entry_price * 1.005
                risk = sl_price - entry_price
                tp_price = entry_price - (risk * self.sl_tp_ratio)

            else:
                sl_price, tp_price = entry_price, entry_price

        sl_price = round(sl_price, 5)
        tp_price = round(tp_price, 5)

        volume = self._calculate_lot_volume(
            account_balance=account_balance,
            risk_percentage=self.risk_percentage,
            entry_price=entry_price,
            sl_price=sl_price,
            symbol_info=symbol_info
        )

        return {
            "sl_price": sl_price,
            "tp_price": tp_price,
            "volume": volume
        }

    def evaluate_exit(
        self,
        position: Any,
        dataframe: pd.DataFrame
    ) -> Optional[Dict[str, Any]]:
        if self.close_strategy and self.close_strategy.evaluate_position(position, dataframe):
            latest_close = float(dataframe.iloc[-1]['close']) if dataframe is not None and not dataframe.empty else 0.0
            return {
                "should_close": True,
                "exit_price": latest_close,
                "exit_reason": "CHOCH_EARLY_EXIT"
            }
        return None
