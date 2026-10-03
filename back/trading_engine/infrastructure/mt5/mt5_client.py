import logging
import threading
from typing import Optional, Dict, Any, Union, List, Tuple
import pandas as pd
import MetaTrader5 as mt5
from django.conf import settings

from .base_client import BaseMT5Client

logger = logging.getLogger(__name__)


class MT5Client(BaseMT5Client):
    """
    Robust singleton wrapper for MetaTrader 5 API integration.
    Handles connection lifecycle, error logging, rates retrieval, and order execution.
    """

    _instance: Optional['MT5Client'] = None
    _lock: threading.Lock = threading.Lock()

    def __new__(cls) -> 'MT5Client':
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super(MT5Client, cls).__new__(cls)
                    cls._instance._initialized = False
        return cls._instance

    def __init__(self) -> None:
        if getattr(self, '_initialized', False):
            return

        self._connected: bool = False
        self._login: Optional[int] = None
        self._server: Optional[str] = None
        self._path: Optional[str] = None
        self._timeout: int = 60000
        self._initialized = True

    def initialize(
        self,
        path: Optional[str] = None,
        login: Optional[int] = None,
        password: Optional[str] = None,
        server: Optional[str] = None,
        timeout: Optional[int] = None,
        portable: bool = False
    ) -> bool:
        with self._lock:
            path = path or getattr(settings, 'MT5_PATH', None)
            login = login or getattr(settings, 'MT5_LOGIN', None)
            password = password or getattr(settings, 'MT5_PASSWORD', None)
            server = server or getattr(settings, 'MT5_SERVER', None)
            timeout = timeout or getattr(settings, 'MT5_TIMEOUT', 60000)

            init_kwargs: Dict[str, Any] = {}
            if path:
                init_kwargs['path'] = path
            if timeout:
                init_kwargs['timeout'] = timeout
            if portable:
                init_kwargs['portable'] = portable
            if login:
                init_kwargs['login'] = int(login)
            if password:
                init_kwargs['password'] = password
            if server:
                init_kwargs['server'] = server

            logger.info("Initializing MetaTrader 5 connection...")
            success = mt5.initialize(**init_kwargs)

            if not success:
                err_code, err_msg = mt5.last_error()
                logger.error("MT5 Initialization failed. Error [%d]: %s", err_code, err_msg)
                self._connected = False
                return False

            self._connected = True
            self._login = login
            self._server = server
            self._path = path
            self._timeout = timeout

            account_info = mt5.account_info()
            if account_info is not None:
                logger.info(
                    "MT5 Connected successfully. Account: %d, Server: %s, Currency: %s, Balance: %.2f",
                    account_info.login,
                    account_info.server,
                    account_info.currency,
                    account_info.balance
                )
            else:
                logger.info("MT5 Connected to terminal (no account specific info).")

            return True

    def ensure_connected(self) -> bool:
        if self._connected:
            terminal_info = mt5.terminal_info()
            if terminal_info is not None and terminal_info.connected:
                return True
            logger.warning("MT5 terminal disconnected or unresponsive. Attempting re-initialization.")
            self._connected = False

        return self.initialize(
            path=self._path,
            login=self._login,
            server=self._server,
            timeout=self._timeout
        )

    def shutdown(self) -> None:
        with self._lock:
            if self._connected:
                mt5.shutdown()
                self._connected = False
                logger.info("MetaTrader 5 connection shut down.")

    @property
    def is_connected(self) -> bool:
        return self._connected

    def fetch_candles(self, symbol: str, timeframe: int, count: int = 100) -> Optional[pd.DataFrame]:
        df = self.copy_rates_from_pos(symbol=symbol, timeframe=timeframe, start_pos=0, count=count)
        return df if not df.empty else None

    def copy_rates_from_pos(
        self,
        symbol: str,
        timeframe: int,
        start_pos: int = 0,
        count: int = 100
    ) -> pd.DataFrame:
        if not self.ensure_connected():
            return pd.DataFrame()

        symbol_info = mt5.symbol_info(symbol)
        if symbol_info is None:
            logger.error("Symbol %s not found in MT5 terminal.", symbol)
            return pd.DataFrame()

        if not symbol_info.visible:
            if not mt5.symbol_select(symbol, True):
                logger.error("Failed to select symbol %s in Market Watch.", symbol)
                return pd.DataFrame()

        rates = mt5.copy_rates_from_pos(symbol, timeframe, start_pos, count)
        if rates is None or len(rates) == 0:
            logger.warning("No rates returned for symbol %s (TF: %d, start: %d, count: %d).",
                           symbol, timeframe, start_pos, count)
            return pd.DataFrame()

        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        return df

    def account_info(self) -> Any:
        if not self.ensure_connected():
            return None
        return mt5.account_info()

    def symbol_info(self, symbol: str) -> Any:
        if not self.ensure_connected():
            return None
        return mt5.symbol_info(symbol)

    def symbol_info_tick(self, symbol: str) -> Any:
        if not self.ensure_connected():
            return None
        return mt5.symbol_info_tick(symbol)

    def get_account_info(self) -> Optional[Dict[str, Any]]:
        if not self.ensure_connected():
            return None

        info = mt5.account_info()
        if info is None:
            return None

        return {
            "login": info.login,
            "trade_mode": info.trade_mode,
            "leverage": info.leverage,
            "balance": info.balance,
            "equity": info.equity,
            "profit": info.profit,
            "margin": info.margin,
            "margin_free": info.margin_free,
            "currency": info.currency,
            "server": info.server,
            "company": info.company,
        }

    def get_symbol_info(self, symbol: str) -> Optional[Any]:
        if not self.ensure_connected():
            return None
        return mt5.symbol_info(symbol)

    def get_positions(self, symbol: Optional[str] = None) -> List[Dict[str, Any]]:
        if not self.ensure_connected():
            return []

        positions = mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()
        if positions is None:
            return []

        result = []
        for pos in positions:
            result.append({
                "ticket": pos.ticket,
                "symbol": pos.symbol,
                "type": "BUY" if pos.type == mt5.ORDER_TYPE_BUY else "SELL",
                "volume": pos.volume,
                "price_open": pos.price_open,
                "sl": pos.sl,
                "tp": pos.tp,
                "profit": pos.profit,
                "time": pos.time,
                "comment": pos.comment,
            })
        return result

    def place_market_order(
        self,
        symbol: str,
        order_type: str,
        volume: float,
        sl: Optional[float] = None,
        tp: Optional[float] = None,
        comment: str = "AlgorithmicTrader Order"
    ) -> Dict[str, Any]:
        if not self.ensure_connected():
            return {"success": False, "error": "MT5 not connected"}

        symbol_info = mt5.symbol_info(symbol)
        if symbol_info is None:
            return {"success": False, "error": f"Symbol {symbol} not found"}

        if not symbol_info.visible:
            mt5.symbol_select(symbol, True)

        order_type_mt5 = mt5.ORDER_TYPE_BUY if order_type.upper() == "BUY" else mt5.ORDER_TYPE_SELL
        price = mt5.symbol_info_tick(symbol).ask if order_type.upper() == "BUY" else mt5.symbol_info_tick(symbol).bid

        deviation = getattr(settings, 'MT5_DEVIATION', 20)

        filling_type = mt5.ORDER_FILLING_IOC
        if hasattr(symbol_info, 'filling_mode') and symbol_info.filling_mode is not None:
            if symbol_info.filling_mode & mt5.ORDER_FILLING_FOK:
                filling_type = mt5.ORDER_FILLING_FOK
            elif symbol_info.filling_mode & mt5.ORDER_FILLING_IOC:
                filling_type = mt5.ORDER_FILLING_IOC
            elif symbol_info.filling_mode & mt5.ORDER_FILLING_RETURN:
                filling_type = mt5.ORDER_FILLING_RETURN
            elif symbol_info.filling_mode & mt5.ORDER_FILLING_RETURN:
                filling_type = mt5.ORDER_FILLING_RETURN

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": float(volume),
            "type": order_type_mt5,
            "price": float(price),
            "deviation": int(deviation),
            "magic": 1001,
            "comment": comment,
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": filling_type,
        }

        if sl is not None and sl > 0:
            request["sl"] = float(sl)
        if tp is not None and tp > 0:
            request["tp"] = float(tp)

        logger.info("Sending MT5 order request: %s", request)
        result = self.order_send(request)

        if result is None:
            err_code, err_msg = mt5.last_error()
            return {"success": False, "error": f"Order send failed. Error [{err_code}]: {err_msg}"}

        if result.retcode != mt5.TRADE_RETCODE_DONE:
            return {
                "success": False,
                "retcode": result.retcode,
                "error": f"Order execution failed with retcode {result.retcode}: {result.comment}"
            }

        logger.info("Order executed successfully! Deal: %d, Order: %d, Price: %.5f, Volume: %.2f",
                    result.deal, result.order, result.price, result.volume)

        return {
            "success": True,
            "deal": getattr(result, 'deal', 0),
            "order": getattr(result, 'order', 0),
            "volume": getattr(result, 'volume', float(volume)),
            "price": getattr(result, 'price', 0.0),
            "bid": getattr(result, 'bid', getattr(result, 'price', 0.0)),
            "ask": getattr(result, 'ask', getattr(result, 'price', 0.0)),
            "comment": getattr(result, 'comment', 'Done'),
        }

    def order_send(self, request: Dict[str, Any]) -> Any:
        if not self.ensure_connected():
            return None
        return mt5.order_send(request)

    def positions_get(self, symbol: Optional[str] = None, ticket: Optional[int] = None) -> Any:
        if not self.ensure_connected():
            return None
        if ticket is not None:
            return mt5.positions_get(ticket=ticket)
        if symbol:
            return mt5.positions_get(symbol=symbol)
        return mt5.positions_get()

    def close_position(self, position_id: int) -> Dict[str, Any]:
        if not self.ensure_connected():
            return {"success": False, "error": "MT5 not connected"}

        positions = mt5.positions_get(ticket=position_id)
        if not positions:
            return {"success": False, "error": f"Position #{position_id} not found"}

        position = positions[0]
        symbol = position.symbol
        volume = position.volume
        pos_type = position.type

        close_type = mt5.ORDER_TYPE_SELL if pos_type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            return {"success": False, "error": f"Failed to get tick price for {symbol}"}

        price = tick.bid if pos_type == mt5.ORDER_TYPE_BUY else tick.ask

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": volume,
            "type": close_type,
            "position": position_id,
            "price": price,
            "deviation": 20,
            "magic": 1001,
            "comment": "AlgorithmicTrader Close",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = mt5.order_send(request)
        if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
            err = result.comment if result else "Unknown error"
            return {"success": False, "error": f"Close position failed: {err}"}

        return {"success": True, "deal": result.deal, "order": result.order}
