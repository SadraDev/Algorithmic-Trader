from .views import (
    status_view,
    execute_cycle_view,
    instances_view,
    stop_instance_view,
    configs_view,
    history_view,
    backtest_view,
    evaluate_indicator_view,
)
from .urls import urlpatterns

__all__ = [
    "status_view",
    "execute_cycle_view",
    "instances_view",
    "stop_instance_view",
    "configs_view",
    "history_view",
    "backtest_view",
    "evaluate_indicator_view",
    "urlpatterns",
]
