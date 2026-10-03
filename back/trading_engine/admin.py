from django.contrib import admin
from .models import StrategyConfig, StrategyInstance, TradeDeal


@admin.register(StrategyConfig)
class StrategyConfigAdmin(admin.ModelAdmin):
    list_display = ('name', 'symbol', 'timeframe', 'risk_percentage', 'sl_tp_ratio', 'operator', 'is_active', 'created_at')
    list_filter = ('is_active', 'symbol', 'operator')
    search_fields = ('name', 'symbol')


@admin.register(StrategyInstance)
class StrategyInstanceAdmin(admin.ModelAdmin):
    list_display = ('id', 'name', 'symbol', 'timeframe', 'is_running', 'latest_score', 'created_at')
    list_filter = ('is_running', 'symbol')
    search_fields = ('name', 'symbol')


@admin.register(TradeDeal)
class TradeDealAdmin(admin.ModelAdmin):
    list_display = ('ticket', 'symbol', 'type', 'volume', 'price', 'profit', 'time')
    list_filter = ('type', 'symbol')
    search_fields = ('symbol', 'ticket', 'comment')
