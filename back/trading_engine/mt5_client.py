"""
MetaTrader 5 Client Wrapper Module.
Provides a thread-safe singleton interface for MT5 API operations.
"""

import logging
import threading
from typing import Optional, Dict, Any, Union, List, Tuple
import pandas as pd
import MetaTrader5 as mt5
from django.conf import settings

logger = logging.getLogger(__name__)


class MT5Client:
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
        """
        Initializes connection to MetaTrader 5 terminal with optional credentials.
        Fallback to Django settings if parameters are omitted.
        """
        with self._lock:
            # Fallback to settings if parameters are not provided
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

            # Log account details if logged in
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
        """
        Checks current connection state and attempts reconnection if disconnected.
        """
        if self._connected:
            # Verify terminal state
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
        """
        Safely closes the connection to the MetaTrader 5 terminal.
        """
        with self._lock:
            if self._connected:
                mt5.shutdown()
                self._connected = False
                logger.info("MetaTrader 5 connection shut down.")

    @property
    def is_connected(self) -> bool:
        """Returns True if MT5 is initialized and connected."""
        return self._connected

    def copy_rates_from_pos(
        self,
        symbol: str,
        timeframe: int,
        start_pos: int = 0,
        count: int = 100
    ) -> pd.DataFrame:
        """
        Retrieves historical bar data for a given symbol and timeframe.
        Converts array structure to pandas DataFrame with formatted timestamps.
        """
        if not self.ensure_connected():
            raise ConnectionError("Failed to connect to MT5 terminal.")

        rates = mt5.copy_rates_from_pos(symbol, timeframe, start_pos, count)
        if rates is None or len(rates) == 0:
            err_code, err_msg = mt5.last_error()
            logger.error("Failed to copy rates for %s. Error [%d]: %s", symbol, err_code, err_msg)
            return pd.DataFrame()

        df = pd.DataFrame(rates)
        if 'time' in df.columns:
            df['time'] = pd.to_datetime(df['time'], unit='s')

        # Standardize expected columns
        expected_cols = ['time', 'open', 'high', 'low', 'close', 'tick_volume', 'spread', 'real_volume']
        for col in expected_cols:
            if col not in df.columns and col != 'real_volume':
                logger.warning("Missing expected column %s in rates DataFrame", col)

        return df

    def symbol_info(self, symbol: str) -> Optional[Any]:
        """
        Fetches symbol metadata (tick size, lot limits, point value, contract size).
        """
        if not self.ensure_connected():
            return None

        info = mt5.symbol_info(symbol)
        if info is None:
            err_code, err_msg = mt5.last_error()
            logger.error("Failed to get symbol info for %s. Error [%d]: %s", symbol, err_code, err_msg)
            return None

        if not info.select:
            if not mt5.symbol_select(symbol, True):
                logger.warning("Failed to select symbol %s in Market Watch", symbol)

        return info

    def symbol_info_tick(self, symbol: str) -> Optional[Any]:
        """
        Fetches current tick prices (ask, bid, last) for a symbol.
        """
        if not self.ensure_connected():
            return None

        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            err_code, err_msg = mt5.last_error()
            logger.error("Failed to get tick info for %s. Error [%d]: %s", symbol, err_code, err_msg)
            return None
        return tick

    def account_info(self) -> Optional[Any]:
        """
        Fetches current account information (balance, equity, margin, free margin).
        """
        if not self.ensure_connected():
            return None

        info = mt5.account_info()
        if info is None:
            err_code, err_msg = mt5.last_error()
            logger.error("Failed to get account info. Error [%d]: %s", err_code, err_msg)
            return None
        return info

    def order_send(self, request: Dict[str, Any]) -> Any:
        """
        Sends an order request to MT5 terminal and logs result or errors.
        """
        if not self.ensure_connected():
            raise ConnectionError("Cannot send order: MT5 not connected.")

        logger.info("Sending MT5 order request: %s", request)
        result = mt5.order_send(request)

        if result is None:
            err_code, err_msg = mt5.last_error()
            logger.error("Order send failed without result structure. Error [%d]: %s", err_code, err_msg)
            return None

        if result.retcode != mt5.TRADE_RETCODE_DONE:
            err_code, err_msg = mt5.last_error()
            logger.error(
                "Order execution failed. Retcode: %d (%s), MT5 Error [%d]: %s",
                result.retcode,
                getattr(result, 'comment', ''),
                err_code,
                err_msg
            )
        else:
            logger.info(
                "Order executed successfully! Deal: %s, Order: %s, Price: %.5f, Volume: %.2f",
                getattr(result, 'deal', 0),
                getattr(result, 'order', 0),
                getattr(result, 'price', 0.0),
                getattr(result, 'volume', 0.0)
            )

        return result

    def positions_get(
        self,
        symbol: Optional[str] = None,
        ticket: Optional[int] = None
    ) -> Optional[Union[List[Any], Tuple[Any, ...]]]:
        """
        Retrieves open positions filtered by symbol or ticket.
        """
        if not self.ensure_connected():
            return None

        kwargs: Dict[str, Any] = {}
        if symbol:
            kwargs['symbol'] = symbol
        if ticket:
            kwargs['ticket'] = ticket

        positions = mt5.positions_get(**kwargs)
        if positions is None:
            err_code, err_msg = mt5.last_error()
            logger.error("Failed to retrieve positions. Error [%d]: %s", err_code, err_msg)
            return None

        return list(positions)

    def close_position(self, position: Any, deviation: int = 20) -> Any:
        """
        Closes an open position by creating a counter order.
        """
        if not self.ensure_connected():
            raise ConnectionError("Cannot close position: MT5 not connected.")

        symbol = position.symbol
        tick = self.symbol_info_tick(symbol)
        if tick is None:
            logger.error("Cannot close position %s: Failed to fetch tick price", position.ticket)
            return None

        # Position type: 0 = POSITION_TYPE_BUY, 1 = POSITION_TYPE_SELL
        if position.type == mt5.POSITION_TYPE_BUY:
            order_type = mt5.ORDER_TYPE_SELL
            price = tick.bid
        else:
            order_type = mt5.ORDER_TYPE_BUY
            price = tick.ask

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "position": position.ticket,
            "symbol": symbol,
            "volume": position.volume,
            "type": order_type,
            "price": price,
            "deviation": deviation,
            "magic": position.magic,
            "comment": "python trading_engine early close",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        logger.info("Executing close order for position #%s on %s", position.ticket, symbol)
        return self.order_send(request)

    def get_history_deals(
        self,
        from_date: Optional[Any] = None,
        to_date: Optional[Any] = None,
        group: str = "*"
    ) -> List[Dict[str, Any]]:
        """
        Retrieves historical deals directly from connected MT5 account using mt5.history_deals_get().
        Consolidates entry and exit deals by matching position_id into unified round-trip position records.
        """
        if not self.ensure_connected():
            return []

        import datetime
        from_date = from_date or (datetime.datetime.now() - datetime.timedelta(days=90))
        to_date = to_date or (datetime.datetime.now() + datetime.timedelta(days=1))

        deals = mt5.history_deals_get(from_date, to_date, group=group)
        if deals is None or len(deals) == 0:
            return []

        # Group deals by position_id
        positions_map: Dict[int, List[Any]] = {}
        for d in deals:
            deal_type = getattr(d, 'type', None)
            if deal_type not in (0, 1):  # 0=BUY, 1=SELL
                continue

            pos_id = getattr(d, 'position_id', None) or getattr(d, 'ticket', 0)
            if pos_id not in positions_map:
                positions_map[pos_id] = []
            positions_map[pos_id].append(d)

        consolidated_records = []

        for pos_id, deal_list in positions_map.items():
            deal_list.sort(key=lambda x: getattr(x, 'time', 0))

            entry_deal = deal_list[0]
            exit_deal = deal_list[-1] if len(deal_list) > 1 else None

            entry_type = getattr(entry_deal, 'type', 0)
            direction = "BUY" if entry_type == 0 else "SELL"
            symbol = getattr(entry_deal, 'symbol', 'N/A')
            volume = getattr(entry_deal, 'volume', 0.0)
            open_price = getattr(entry_deal, 'price', 0.0)

            open_ts = getattr(entry_deal, 'time', 0)
            open_dt = datetime.datetime.fromtimestamp(open_ts) if open_ts > 0 else datetime.datetime.now()
            open_time_str = open_dt.strftime('%Y-%m-%d %H:%M:%S') if open_ts > 0 else "N/A"

            if exit_deal and exit_deal != entry_deal:
                close_price = getattr(exit_deal, 'price', open_price)
                close_ts = getattr(exit_deal, 'time', open_ts)
                close_dt = datetime.datetime.fromtimestamp(close_ts) if close_ts > 0 else open_dt
                close_time_str = close_dt.strftime('%Y-%m-%d %H:%M:%S') if close_ts > 0 else "N/A"
                net_profit = sum(getattr(d, 'profit', 0.0) + getattr(d, 'swap', 0.0) + getattr(d, 'commission', 0.0) for d in deal_list)

                # Duration formatting
                secs = max(0, int((close_dt - open_dt).total_seconds()))
                hrs = secs // 3600
                mins = (secs % 3600) // 60
                s = secs % 60
                if hrs > 0:
                    duration_str = f"{hrs}h {mins}m {s}s"
                elif mins > 0:
                    duration_str = f"{mins}m {s}s"
                else:
                    duration_str = f"{s}s"
            else:
                close_price = open_price
                close_time_str = open_time_str
                net_profit = getattr(entry_deal, 'profit', 0.0) + getattr(entry_deal, 'swap', 0.0) + getattr(entry_deal, 'commission', 0.0)
                duration_str = "Open / N/A"

            consolidated_records.append({
                "position_id": pos_id,
                "ticket": pos_id,
                "symbol": symbol,
                "direction": direction,
                "type": direction,
                "volume": volume,
                "open_price": round(open_price, 5),
                "close_price": round(close_price, 5),
                "price": round(close_price, 5),
                "open_time": open_time_str,
                "close_time": close_time_str,
                "timestamp": close_time_str,
                "duration": duration_str,
                "profit": round(net_profit, 2),
                "comment": getattr(entry_deal, 'comment', ''),
            })

        consolidated_records.sort(key=lambda x: x["close_time"], reverse=True)
        return consolidated_records
