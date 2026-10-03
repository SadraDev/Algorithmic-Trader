from django.db import models


class TradeDeal(models.Model):
    """
    Persists historical MT5 executed order deals and closed trade PnL records.
    """
    ticket = models.BigIntegerField(unique=True, db_index=True)
    order = models.BigIntegerField(default=0)
    symbol = models.CharField(max_length=20, db_index=True)
    type = models.CharField(max_length=10)  # BUY or SELL
    volume = models.FloatField(default=0.0)
    price = models.FloatField(default=0.0)
    profit = models.FloatField(default=0.0)
    comment = models.CharField(max_length=200, blank=True, null=True)
    time = models.DateTimeField(db_index=True)

    def __str__(self) -> str:
        return f"Deal #{self.ticket} [{self.symbol} {self.type}] PnL: ${self.profit:.2f}"
