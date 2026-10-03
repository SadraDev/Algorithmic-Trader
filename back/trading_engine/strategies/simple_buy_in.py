from typing import Optional, Any, Dict
import pandas as pd

from .base import BaseBuyInStrategy


class SimpleBuyInStrategy(BaseBuyInStrategy):
    """
    Simple Buy-in Strategy.
    Consumes Risk %, SL/TP Ratio, and Max Concurrent Open Positions.
    Dynamically calculates Stop Loss (SL) by back-tracing from the trigger candle to identify
    the nearest local extrema (local minimum for BUY, local maximum for SELL) on execution timeframe.
    Calculates Take Profit (TP) and Lot Size relative to this dynamic SL distance.
    Does NOT execute unassigned or hidden early exit rules.
    """

    def __init__(
        self,
        risk_percentage: float = 1.0,
        sl_tp_ratio: float = 2.0,
        max_active_positions: int = 1,
        swing_lookback: int = 15,
        **kwargs: Any
    ) -> None:
        super().__init__(risk_percentage, sl_tp_ratio, max_active_positions)
        self.swing_lookback = swing_lookback

    def calculate_trade_parameters(
        self,
        signal: int,
        entry_price: float,
        dataframe: pd.DataFrame,
        account_balance: float,
        symbol_info: Optional[Any] = None
    ) -> Dict[str, Any]:
        if dataframe is None or len(dataframe) < 2:
            default_offset = entry_price * (self.risk_percentage / 100.0)
            if default_offset <= 0:
                default_offset = entry_price * 0.005

            if signal == 1:
                sl_price = entry_price - default_offset
                tp_price = entry_price + (default_offset * self.sl_tp_ratio)
            else:
                sl_price = entry_price + default_offset
                tp_price = entry_price - (default_offset * self.sl_tp_ratio)
        else:
            recent_df = dataframe.tail(min(self.swing_lookback, len(dataframe)))

            if signal == 1:  # BUY: local minimum low extrema
                lowest_low = float(recent_df['low'].min())
                buffer = max((entry_price - lowest_low) * 0.05, entry_price * 0.0003)
                sl_price = lowest_low - buffer
                if sl_price >= entry_price:
                    sl_price = entry_price * 0.995

                risk = entry_price - sl_price
                tp_price = entry_price + (risk * self.sl_tp_ratio)

            elif signal == -1:  # SELL: local maximum high extrema
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
        # Simple Buy-in has no unassigned or hidden exits
        return None
