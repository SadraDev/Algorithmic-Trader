from django.contrib import admin
from .models import StrategyConfig, TradeLog


@admin.register(StrategyConfig)
class StrategyConfigAdmin(admin.ModelAdmin):
    list_display = ('name', 'symbol', 'timeframe', 'risk_percentage', 'sl_tp_ratio', 'operator', 'is_active', 'created_at')
    list_filter = ('is_active', 'symbol', 'operator')
    search_fields = ('name', 'symbol')


@admin.register(TradeLog)
class TradeLogAdmin(admin.ModelAdmin):
    list_display = ('timestamp', 'symbol', 'action', 'signal', 'price', 'volume', 'sl_price', 'tp_price', 'ticket')
    list_filter = ('action', 'symbol', 'signal')
    search_fields = ('symbol', 'ticket', 'comment')
