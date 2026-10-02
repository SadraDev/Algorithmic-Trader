from django.urls import path
from . import views

urlpatterns = [
    path('status/', views.status_view, name='trading_status'),
    path('execute/', views.execute_cycle_view, name='trading_execute'),
    path('configs/', views.configs_view, name='trading_configs'),
    path('logs/', views.logs_view, name='trading_logs'),
    path('indicators/', views.indicators_list_view, name='indicators_list'),
    path('indicators/evaluate/', views.indicators_evaluate_view, name='indicators_evaluate'),
    path('instances/', views.instances_view, name='instances_list'),
    path('instances/<str:instance_id>/pause/', views.instance_pause_view, name='instance_pause'),
    path('instances/<str:instance_id>/stop/', views.instance_stop_view, name='instance_stop'),
    path('history/', views.history_deals_view, name='history_deals'),
]
