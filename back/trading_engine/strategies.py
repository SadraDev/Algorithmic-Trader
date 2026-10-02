"""
Trading Strategies Module.
Implements OpenStrategy (swing extrema SL/TP, max active position capping, position sizing)
and CloseStrategy (early position exit detection via Change of Character / CHoCH).
"""

import logging
import math
from typing import Tuple, Optional, Any
import pandas as pd

logger = logging.getLogger(__name__)


class OpenStrategy:
    """
    Handles trade setup validation, swing extrema stop-loss/take-profit calculation,
    max active position checks, and risk-managed lot sizing.
    """

    def __init__(
        self,
        risk_percentage: float = 1.0,
        sl_tp_ratio: float = 2.0,
        max_active_positions: int = 1,
        require_engulfing: bool = False
    ) -> None:
        if risk_percentage <= 0 or risk_percentage > 100:
            raise ValueError("risk_percentage must be between 0 and 100")
        if sl_tp_ratio <= 0:
            raise ValueError("sl_tp_ratio must be greater than 0")

        self.risk_percentage = risk_percentage
        self.sl_tp_ratio = sl_tp_ratio
        self.max_active_positions = max(1, int(max_active_positions))
        self.require_engulfing = require_engulfing

    def validate_trigger(self, signal: int, dataframe: pd.DataFrame) -> bool:
        """
        Validates whether signal aligns with execution condition (Bullish or Bearish Engulfing Candle).
        """
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
        """
        Calculates Stop Loss (SL) using market structure (local swing low/high extrema across recent candles)
        and Take Profit (TP) dynamically by projecting Entry-SL risk using SL/TP ratio.

        :param signal: 1 for Long, -1 for Short
        :param entry_price: Planned entry price
        :param dataframe: Recent price DataFrame
        :param sl_tp_ratio: Optional override for SL:TP risk-reward ratio
        :param swing_lookback: Number of recent candles to inspect for swing extrema
        :return: Tuple (sl_price, tp_price)
        """
        ratio = sl_tp_ratio if sl_tp_ratio is not None else self.sl_tp_ratio

        if dataframe is None or len(dataframe) < 2:
            default_offset = entry_price * 0.005
            if signal == 1:
                sl = entry_price - default_offset
                tp = entry_price + (default_offset * ratio)
            else:
                sl = entry_price + default_offset
                tp = entry_price - (default_offset * ratio)
            return round(sl, 5), round(tp, 5)

        recent_df = dataframe.tail(min(swing_lookback, len(dataframe)))

        if signal == 1:
            lowest_low = float(recent_df['low'].min())
            buffer = max((entry_price - lowest_low) * 0.05, entry_price * 0.0003)
            sl_price = lowest_low - buffer

            if sl_price >= entry_price:
                sl_price = entry_price * 0.995

            risk = entry_price - sl_price
            tp_price = entry_price + (risk * ratio)

        elif signal == -1:
            highest_high = float(recent_df['high'].max())
            buffer = max((highest_high - entry_price) * 0.05, entry_price * 0.0003)
            sl_price = highest_high + buffer

            if sl_price <= entry_price:
                sl_price = entry_price * 1.005

            risk = sl_price - entry_price
            tp_price = entry_price - (risk * ratio)

        else:
            sl_price, tp_price = entry_price, entry_price

        return round(sl_price, 5), round(tp_price, 5)

    def calculate_position_size(
        self,
        account_balance: float,
        risk_percentage: float,
        entry_price: float,
        sl_price: float,
        symbol_info: Optional[Any] = None
    ) -> float:
        """
        Calculates position volume (lots) according to account balance, risk percentage, and distance to extrema SL.
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
                if loss_per_lot > 0:
                    raw_lots = risk_amount / loss_per_lot
                else:
                    raw_lots = 0.01
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


class CloseStrategy:
    """
    Evaluates currently open trades and detects early exit conditions,
    such as Change of Character (CHoCH) price action reversals.
    """

    def __init__(self, choch_window: int = 5) -> None:
        self.choch_window = choch_window

    def evaluate_position(self, position: Any, dataframe: pd.DataFrame) -> bool:
        if dataframe is None or len(dataframe) < (self.choch_window + 2):
            return False

        pos_type = getattr(position, 'type', None)
        if pos_type is None and isinstance(position, dict):
            pos_type = position.get('type')

        if pos_type is None:
            return False

        recent_df = dataframe.tail(self.choch_window + 2)
        window_df = recent_df.iloc[:-1]
        latest_candle = recent_df.iloc[-1]

        if pos_type == 0:  # BUY position
            swing_low = window_df['low'].min()
            if latest_candle['close'] < swing_low:
                logger.info(
                    "Bearish CHoCH detected for BUY position #%s (Close: %.5f < Swing Low: %.5f). Early close triggered.",
                    getattr(position, 'ticket', 'N/A'),
                    latest_candle['close'],
                    swing_low
                )
                return True

        elif pos_type == 1:  # SELL position
            swing_high = window_df['high'].max()
            if latest_candle['close'] > swing_high:
                logger.info(
                    "Bullish CHoCH detected for SELL position #%s (Close: %.5f > Swing High: %.5f). Early close triggered.",
                    getattr(position, 'ticket', 'N/A'),
                    latest_candle['close'],
                    swing_high
                )
                return True

        return False
