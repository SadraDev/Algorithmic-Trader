from django.db import models


class StrategyConfig(models.Model):
    """
    Model representing trading strategy configurations.
    """
    OPERATOR_CHOICES = [
        ('WEIGHTED', 'WEIGHTED (Weighted Average Signal)'),
        ('AND', 'AND (All algorithms must agree)'),
        ('OR', 'OR (Any algorithm triggers signal)'),
    ]

    name = models.CharField(max_length=100, unique=True, help_text="Config name identifier")
    symbol = models.CharField(max_length=20, default="EURUSD", help_text="Trading symbol (e.g., EURUSD)")
    timeframe = models.IntegerField(default=5, help_text="MT5 timeframe minutes (e.g., 5 for M5)")
    risk_percentage = models.FloatField(default=1.0, help_text="Account balance risk percentage per trade")
    sl_tp_ratio = models.FloatField(default=2.0, help_text="Take Profit to Stop Loss distance ratio")
    operator = models.CharField(max_length=10, choices=OPERATOR_CHOICES, default='WEIGHTED', help_text="Algorithm combiner operator")
    signal_threshold = models.FloatField(default=0.5, help_text="Continuous indicator signal threshold (0.1 to 0.9)")
    config_json = models.JSONField(default=dict, blank=True, help_text="Full serialized indicator pipeline configuration")
    is_active = models.BooleanField(default=True, help_text="Whether strategy is active")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self) -> str:
        return f"{self.name} ({self.symbol} - M{self.timeframe}, Thresh: {self.signal_threshold})"


class TradeLog(models.Model):
    """
    Model recording trading execution history, signals, orders, and position exits.
    """
    ACTION_CHOICES = [
        ('OPEN_BUY', 'Opened Buy Position'),
        ('OPEN_SELL', 'Opened Sell Position'),
        ('CLOSE_EARLY', 'Closed Position Early (CHoCH)'),
        ('SIGNAL_SKIP', 'Signal Evaluated (Trigger Unconfirmed)'),
    ]

    config = models.ForeignKey(StrategyConfig, on_delete=models.SET_NULL, null=True, blank=True, related_name='trade_logs')
    symbol = models.CharField(max_length=20)
    action = models.CharField(max_length=20, choices=ACTION_CHOICES)
    signal = models.IntegerField(help_text="Evaluated signal (-1, 0, 1)")
    price = models.FloatField(null=True, blank=True, help_text="Entry or Exit price")
    volume = models.FloatField(null=True, blank=True, help_text="Lot volume")
    sl_price = models.FloatField(null=True, blank=True, help_text="Stop loss level")
    tp_price = models.FloatField(null=True, blank=True, help_text="Take profit level")
    ticket = models.BigIntegerField(null=True, blank=True, help_text="MT5 Order/Position ticket")
    comment = models.TextField(blank=True, default="")
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-timestamp']

    def __str__(self) -> str:
        return f"[{self.timestamp.strftime('%Y-%m-%d %H:%M:%S')}] {self.action} on {self.symbol} (Ticket #{self.ticket or 'N/A'})"
