from abc import ABC, abstractmethod
from typing import Optional, Dict, Any, List
import pandas as pd


class BaseMT5Client(ABC):
    """
    Abstract Interface for MT5 Terminal Connection Adapter.
    Decouples execution logic from terminal SDK bindings.
    """

    @abstractmethod
    def ensure_connected(self) -> bool:
        pass

    @abstractmethod
    def fetch_candles(self, symbol: str, timeframe: int, count: int = 100) -> Optional[pd.DataFrame]:
        pass

    @abstractmethod
    def get_account_info(self) -> Optional[Dict[str, Any]]:
        pass

    @abstractmethod
    def get_positions(self, symbol: Optional[str] = None) -> List[Dict[str, Any]]:
        pass

    @abstractmethod
    def place_market_order(
        self,
        symbol: str,
        order_type: str,
        volume: float,
        sl: Optional[float] = None,
        tp: Optional[float] = None,
        comment: str = "AlgorithmicTrader Order"
    ) -> Dict[str, Any]:
        pass

    @abstractmethod
    def close_position(self, position_id: int) -> Dict[str, Any]:
        pass
