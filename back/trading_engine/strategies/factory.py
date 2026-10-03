from typing import Optional, Any

from .base import BaseBuyInStrategy
from .simple_buy_in import SimpleBuyInStrategy
from .swing_extrema import SwingExtremaBuyInStrategy


def get_buy_in_strategy(
    method_name: Optional[str] = None,
    risk_percentage: float = 1.0,
    sl_tp_ratio: float = 2.0,
    max_active_positions: int = 1,
    **kwargs: Any
) -> BaseBuyInStrategy:
    """
    Factory function to instantiate the requested Buy-in strategy.
    """
    name = (method_name or "Simple Buy-in").lower()

    if "swing" in name or "extrema" in name:
        return SwingExtremaBuyInStrategy(
            risk_percentage=risk_percentage,
            sl_tp_ratio=sl_tp_ratio,
            max_active_positions=max_active_positions,
            **kwargs
        )

    # Default: Simple Buy-in (No hidden or unassigned exits)
    return SimpleBuyInStrategy(
        risk_percentage=risk_percentage,
        sl_tp_ratio=sl_tp_ratio,
        max_active_positions=max_active_positions,
        **kwargs
    )
