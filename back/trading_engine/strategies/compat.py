import logging
from typing import Tuple, Optional, Any
import pandas as pd

logger = logging.getLogger(__name__)


class CloseStrategy:
    """
    Evaluates market structure Change of Character (CHoCH) early position exit signals.
    """

    def __init__(self, choch_window: int = 5) -> None:
        self.choch_window = choch_window

    def evaluate_position(
        self,
        position: Any,
        dataframe: pd.DataFrame
    ) -> bool:
        if position is None or dataframe is None or len(dataframe) < (self.choch_window + 1):
            return False

        pos_type = getattr(position, 'type', None)
        pos_id = getattr(position, 'ticket', getattr(position, 'id', 0))

        if pos_type is None and isinstance(position, dict):
            pos_type = position.get('type')
            pos_id = position.get('id', 0)

        type_str = str(pos_type).upper()
        recent_df = dataframe.iloc[-(self.choch_window + 1):-1]
        latest_close = float(dataframe.iloc[-1]['close'])

        if "BUY" in type_str or pos_type == 0:
            recent_low = float(recent_df['low'].min())
            if latest_close < recent_low:
                logger.info(
                    "Bearish CHoCH detected for BUY position #%s (Close: %.5f < Swing Low: %.5f). Early close triggered.",
                    pos_id, latest_close, recent_low
                )
                return True

        elif "SELL" in type_str or pos_type == 1:
            recent_high = float(recent_df['high'].max())
            if latest_close > recent_high:
                logger.info(
                    "Bullish CHoCH detected for SELL position #%s (Close: %.5f > Swing High: %.5f). Early close triggered.",
                    pos_id, latest_close, recent_high
                )
                return True

        return False


class OpenStrategy:
    """
    Backwards-compatible wrapper.
    """

    def __init__(
        self,
        risk_percentage: float = 1.0,
        sl_tp_ratio: float = 2.0,
        max_active_positions: int = 1,
        require_engulfing: bool = False
    ) -> None:
        self.risk_percentage = risk_percentage
        self.sl_tp_ratio = sl_tp_ratio
        self.max_active_positions = max(1, int(max_active_positions))

    def validate_trigger(self, signal: int, dataframe: pd.DataFrame) -> bool:
        if signal == 0 or dataframe is None or len(dataframe) < 2:
            return False

        prev_candle = dataframe.iloc[-2]
        curr_candle = dataframe.iloc[-1]

        prev_open, prev_close = prev_candle['open'], prev_candle['close']
        curr_open, curr_close = curr_candle['open'], curr_candle['close']

        if signal == 1:
            is_prev_bearish = prev_close < prev_open
            is_curr_bullish = curr_close > curr_open
            is_engulfing = (curr_open <= prev_close) and (curr_close >= prev_open)
            return is_prev_bearish and is_curr_bullish and is_engulfing

        elif signal == -1:
            is_prev_bullish = prev_close > prev_open
            is_curr_bearish = curr_close < curr_open
            is_engulfing = (curr_open >= prev_close) and (curr_close <= prev_open)
            return is_prev_bullish and is_curr_bearish and is_engulfing

        return False

    def calculate_sl_tp(
        self,
        signal: int,
        entry_price: float,
        dataframe: pd.DataFrame,
        sl_tp_ratio: Optional[float] = None,
        swing_lookback: int = 15
    ) -> Tuple[float, float]:
        ratio = sl_tp_ratio or self.sl_tp_ratio
        if dataframe is None or len(dataframe) < 2:
            default_offset = entry_price * 0.005
            if signal == 1:
                return entry_price - default_offset, entry_price + (default_offset * ratio)
            else:
                return entry_price + default_offset, entry_price - (default_offset * ratio)

        recent_df = dataframe.tail(min(swing_lookback, len(dataframe)))
        if signal == 1:
            lowest_low = float(recent_df['low'].min())
            buffer = max((entry_price - lowest_low) * 0.05, entry_price * 0.0003)
            sl_price = lowest_low - buffer
            if sl_price >= entry_price:
                sl_price = entry_price * 0.995
            risk = entry_price - sl_price
            tp_price = entry_price + (risk * ratio)
        else:
            highest_high = float(recent_df['high'].max())
            buffer = max((highest_high - entry_price) * 0.05, entry_price * 0.0003)
            sl_price = highest_high + buffer
            if sl_price <= entry_price:
                sl_price = entry_price * 1.005
            risk = sl_price - entry_price
            tp_price = entry_price - (risk * ratio)

        return round(sl_price, 5), round(tp_price, 5)

    def calculate_position_size(
        self,
        account_balance: float,
        risk_percentage: float,
        entry_price: float,
        sl_price: float,
        symbol_info: Optional[Any] = None
    ) -> float:
        from .simple_buy_in import SimpleBuyInStrategy
        strat = SimpleBuyInStrategy(risk_percentage=risk_percentage)
        return strat._calculate_lot_volume(
            account_balance=account_balance,
            risk_percentage=risk_percentage,
            entry_price=entry_price,
            sl_price=sl_price,
            symbol_info=symbol_info
        )
