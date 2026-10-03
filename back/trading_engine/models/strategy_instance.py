from django.db import models


class StrategyInstance(models.Model):
    """
    Represents an active, background daemon worker instance running on a specific asset symbol.
    """
    name = models.CharField(max_length=100)
    symbol = models.CharField(max_length=20, db_index=True)
    timeframe = models.IntegerField(default=5)
    risk_percentage = models.FloatField(default=1.0)
    sl_tp_ratio = models.FloatField(default=2.0)
    max_active_positions = models.IntegerField(default=1)
    operator = models.CharField(max_length=20, default="WEIGHTED")
    signal_threshold = models.FloatField(default=0.5)
    is_running = models.BooleanField(default=True, db_index=True)
    latest_score = models.FloatField(default=0.0)
    config_json = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    def __str__(self) -> str:
        return f"Instance #{self.id}: {self.name} ({self.symbol})"
