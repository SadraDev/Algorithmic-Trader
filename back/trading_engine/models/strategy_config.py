from django.db import models


class StrategyConfig(models.Model):
    """
    Persists asset-agnostic custom algorithm configurations and assigned buy-in parameters.
    """
    name = models.CharField(max_length=100, unique=True, db_index=True)
    symbol = models.CharField(max_length=20, default="EURUSD", db_index=True)
    timeframe = models.IntegerField(default=5)
    risk_percentage = models.FloatField(default=1.0)
    sl_tp_ratio = models.FloatField(default=2.0)
    max_active_positions = models.IntegerField(default=1)
    operator = models.CharField(max_length=20, default="WEIGHTED", db_index=True)
    signal_threshold = models.FloatField(default=0.5)
    config_json = models.JSONField(default=dict)
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"{self.name} [{self.symbol} M{self.timeframe}]"
