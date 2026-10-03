from django.urls import path
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

urlpatterns = [
    path('status/', status_view, name='status'),
    path('execute/', execute_cycle_view, name='execute_cycle'),
    path('instances/', instances_view, name='instances'),
    path('instances/<str:instance_id>/stop/', stop_instance_view, name='stop_instance'),
    path('configs/', configs_view, name='configs'),
    path('history/', history_view, name='history'),
    path('backtest/', backtest_view, name='backtest'),
    path('indicator/evaluate/', evaluate_indicator_view, name='evaluate_indicator'),
]
