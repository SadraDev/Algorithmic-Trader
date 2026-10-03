import logging
import datetime
from typing import Dict, Any, List, Optional, Tuple
import numpy as np
import pandas as pd
import MetaTrader5 as mt5

from .mt5_client import MT5Client
from ...algorithms import AlgorithmCombiner, MACDCrossover, RSIOversold, RSIIndicator, StochasticIndicator, MACDIndicator, BollingerBandsIndicator
from ...strategies import get_buy_in_strategy, BaseBuyInStrategy
from .executor import IndicatorAdapter

logger = logging.getLogger(__name__)


class BacktestEngine:
    """
    Simulates historical trading cycles bar-by-bar without lookahead bias or hidden hardcoded mechanics.
    Delegates SL, TP, lot sizing, and exit checks strictly to the configured BuyInStrategy.
    """

    def __init__(self, client: Optional[MT5Client] = None) -> None:
        self.client = client or MT5Client()

    def run(
        self,
        algorithm_config: Dict[str, Any],
        buy_in_config: Dict[str, Any],
        symbol: str = "EURUSD",
        date_from: Optional[str] = None,
        date_to: Optional[str] = None,
        initial_balance: float = 10000.0,
        timeframe: int = 5
    ) -> Dict[str, Any]:
        logger.info("--- Starting Modular Historical Backtest [%s] ---", symbol)

        dt_from = self._parse_date(date_from, default_days_back=90)
        dt_to = self._parse_date(date_to, default_days_back=0)

        if dt_from >= dt_to:
            dt_from = dt_to - datetime.timedelta(days=30)

        warmup_minutes = timeframe * 250
        warmup_from = dt_from - datetime.timedelta(minutes=warmup_minutes)

        dataframe = self._fetch_historical_data(symbol, timeframe, warmup_from, dt_to)

        if dataframe is None or dataframe.empty or len(dataframe) < 35:
            logger.warning("Insufficient data for backtesting %s. Generating synthetic backtest series.", symbol)
            dataframe = self._generate_synthetic_candles(symbol, warmup_from, dt_to)

        eval_start_indices = dataframe[dataframe['time'] >= dt_from].index
        if len(eval_start_indices) > 0:
            start_eval_idx = max(30, int(eval_start_indices[0]))
        else:
            start_eval_idx = 30

        combiner = self._build_combiner(algorithm_config)

        buy_in_method = buy_in_config.get("method", buy_in_config.get("buyInMethod", "Simple Buy-in"))
        buy_in_strategy: BaseBuyInStrategy = get_buy_in_strategy(
            method_name=buy_in_method,
            risk_percentage=float(buy_in_config.get("risk_percentage", 1.0)),
            sl_tp_ratio=float(buy_in_config.get("sl_tp_ratio", 2.0)),
            max_active_positions=int(buy_in_config.get("max_active_positions", 1))
        )

        current_balance = float(initial_balance)
        peak_balance = float(initial_balance)
        max_drawdown_amount = 0.0
        max_drawdown_pct = 0.0

        active_position: Optional[Dict[str, Any]] = None
        closed_trades: List[Dict[str, Any]] = []
        equity_curve: List[Dict[str, Any]] = []

        total_bars = len(dataframe)

        for i in range(start_eval_idx, total_bars):
            slice_df = dataframe.iloc[:i + 1]
            current_bar = slice_df.iloc[-1]

            bar_time = current_bar['time']
            bar_time_str = bar_time.strftime('%Y-%m-%d %H:%M:%S') if isinstance(bar_time, (datetime.datetime, pd.Timestamp)) else str(bar_time)

            open_p = float(current_bar['open'])
            high_p = float(current_bar['high'])
            low_p = float(current_bar['low'])
            close_p = float(current_bar['close'])

            if active_position is not None:
                pos_type = active_position['type']
                sl_p = active_position['sl_price']
                tp_p = active_position['tp_price']
                entry_p = active_position['entry_price']
                vol = active_position['volume']

                exit_triggered = False
                exit_price = close_p
                exit_reason = "MANUAL"

                if pos_type == "BUY":
                    if low_p <= sl_p:
                        exit_triggered = True
                        exit_price = sl_p
                        exit_reason = "STOP_LOSS"
                    elif high_p >= tp_p:
                        exit_triggered = True
                        exit_price = tp_p
                        exit_reason = "TAKE_PROFIT"

                elif pos_type == "SELL":
                    if high_p >= sl_p:
                        exit_triggered = True
                        exit_price = sl_p
                        exit_reason = "STOP_LOSS"
                    elif low_p <= tp_p:
                        exit_triggered = True
                        exit_price = tp_p
                        exit_reason = "TAKE_PROFIT"

                if not exit_triggered:
                    custom_exit = buy_in_strategy.evaluate_exit(active_position, slice_df)
                    if custom_exit and custom_exit.get("should_close", False):
                        exit_triggered = True
                        exit_price = custom_exit.get("exit_price", close_p)
                        exit_reason = custom_exit.get("exit_reason", "STRATEGY_EXIT")

                if exit_triggered:
                    pnl_points = (exit_price - entry_p) if pos_type == "BUY" else (entry_p - exit_price)
                    contract_size = 100000.0 if "USD" in symbol or "EUR" in symbol else 100.0
                    pnl_amount = pnl_points * vol * contract_size

                    current_balance += pnl_amount

                    candle_slice, entry_s_idx, exit_s_idx = self._extract_candle_slice(
                        dataframe=dataframe,
                        entry_idx=active_position['entry_bar_index'],
                        exit_idx=i,
                        pre_candles=30,
                        post_candles=10
                    )

                    closed_trades.append({
                        "trade_id": len(closed_trades) + 1,
                        "symbol": symbol,
                        "type": pos_type,
                        "volume": vol,
                        "entry_price": round(entry_p, 5),
                        "exit_price": round(exit_price, 5),
                        "sl_price": round(sl_p, 5),
                        "tp_price": round(tp_p, 5),
                        "entry_time": active_position['entry_time'],
                        "exit_time": bar_time_str,
                        "profit": round(pnl_amount, 2),
                        "exit_reason": exit_reason,
                        "candle_slice": candle_slice,
                        "entry_slice_index": entry_s_idx,
                        "exit_slice_index": exit_s_idx
                    })
                    active_position = None

            if active_position is None:
                signal = int(combiner.evaluate(slice_df))

                if signal in (1, -1):
                    entry_p = close_p

                    trade_params = buy_in_strategy.calculate_trade_parameters(
                        signal=signal,
                        entry_price=entry_p,
                        dataframe=slice_df,
                        account_balance=current_balance,
                        symbol_info=None
                    )

                    active_position = {
                        "id": len(closed_trades) + 1,
                        "type": "BUY" if signal == 1 else "SELL",
                        "entry_price": entry_p,
                        "sl_price": trade_params["sl_price"],
                        "tp_price": trade_params["tp_price"],
                        "volume": trade_params["volume"],
                        "entry_time": bar_time_str,
                        "entry_bar_index": i
                    }

            if current_balance > peak_balance:
                peak_balance = current_balance

            dd_dollars = peak_balance - current_balance
            dd_pct = (dd_dollars / peak_balance * 100.0) if peak_balance > 0 else 0.0

            if dd_dollars > max_drawdown_amount:
                max_drawdown_amount = dd_dollars
                max_drawdown_pct = dd_pct

            equity_curve.append({
                "timestamp": bar_time_str,
                "equity": round(current_balance, 2)
            })

        if active_position is not None:
            last_bar = dataframe.iloc[-1]
            last_close = float(last_bar['close'])
            pnl_points = (last_close - active_position['entry_price']) if active_position['type'] == "BUY" else (active_position['entry_price'] - last_close)
            contract_size = 100000.0 if "USD" in symbol or "EUR" in symbol else 100.0
            pnl_amount = pnl_points * active_position['volume'] * contract_size
            current_balance += pnl_amount

            candle_slice, entry_s_idx, exit_s_idx = self._extract_candle_slice(
                dataframe=dataframe,
                entry_idx=active_position['entry_bar_index'],
                exit_idx=total_bars - 1,
                pre_candles=30,
                post_candles=10
            )

            closed_trades.append({
                "trade_id": len(closed_trades) + 1,
                "symbol": symbol,
                "type": active_position['type'],
                "volume": active_position['volume'],
                "entry_price": round(active_position['entry_price'], 5),
                "exit_price": round(last_close, 5),
                "sl_price": round(active_position['sl_price'], 5),
                "tp_price": round(active_position['tp_price'], 5),
                "entry_time": active_position['entry_time'],
                "exit_time": str(last_bar['time']),
                "profit": round(pnl_amount, 2),
                "exit_reason": "END_OF_TEST",
                "candle_slice": candle_slice,
                "entry_slice_index": entry_s_idx,
                "exit_slice_index": exit_s_idx
            })

        total_trades = len(closed_trades)
        winning_trades = sum(1 for t in closed_trades if t['profit'] > 0)
        losing_trades = sum(1 for t in closed_trades if t['profit'] < 0)

        win_rate = round((winning_trades / total_trades * 100.0), 2) if total_trades > 0 else 0.0
        total_net_profit = round(current_balance - initial_balance, 2)
        total_net_profit_pct = round(((current_balance - initial_balance) / initial_balance * 100.0), 2)

        gross_profit = sum(t['profit'] for t in closed_trades if t['profit'] > 0)
        gross_loss = abs(sum(t['profit'] for t in closed_trades if t['profit'] < 0))

        profit_factor = round(gross_profit / gross_loss, 2) if gross_loss > 0 else (round(gross_profit, 2) if gross_profit > 0 else 1.0)

        sampled_equity_curve = self._downsample_points(equity_curve, max_points=150)

        report = {
            "symbol": symbol,
            "date_from": dt_from.strftime('%Y-%m-%d'),
            "date_to": dt_to.strftime('%Y-%m-%d'),
            "initial_balance": initial_balance,
            "final_balance": round(current_balance, 2),
            "total_net_profit": total_net_profit,
            "total_net_profit_pct": total_net_profit_pct,
            "total_trades": total_trades,
            "winning_trades": winning_trades,
            "losing_trades": losing_trades,
            "win_rate": win_rate,
            "profit_factor": profit_factor,
            "max_drawdown_amount": round(max_drawdown_amount, 2),
            "max_drawdown_pct": round(max_drawdown_pct, 2),
            "equity_curve": sampled_equity_curve,
            "trades": closed_trades
        }

        logger.info("--- Modular Backtest Complete [%s]. Net Profit: $%.2f (%d trades) ---", symbol, total_net_profit, total_trades)
        return report

    def _build_combiner(self, config: Dict[str, Any]) -> AlgorithmCombiner:
        indicators_list = config.get("indicators", [])
        operator = config.get("operator", "WEIGHTED")
        threshold = float(config.get("signal_threshold", config.get("threshold", 0.5)))

        algorithm_instances = []
        weights_list = []

        if indicators_list:
            for ind_item in indicators_list:
                ind_id = ind_item.get("id", "rsi")
                params = ind_item.get("params", {})
                w = float(ind_item.get("weight", 0.5))

                if ind_id == "rsi":
                    obj = RSIIndicator(period=int(params.get("period", 14)))
                elif ind_id == "stochastic":
                    obj = StochasticIndicator(
                        k_period=int(params.get("k_period", 14)),
                        d_period=int(params.get("d_period", 3))
                    )
                elif ind_id == "macd":
                    obj = MACDIndicator(
                        fast=int(params.get("fast", 12)),
                        slow=int(params.get("slow", 26)),
                        signal=int(params.get("signal", 9)),
                        z_window=int(params.get("z_window", 100))
                    )
                elif ind_id == "bollinger":
                    obj = BollingerBandsIndicator(
                        period=int(params.get("period", 20)),
                        std_dev=float(params.get("std_dev", 2.0))
                    )
                else:
                    continue

                algorithm_instances.append(IndicatorAdapter(obj))
                weights_list.append(w)

        if not algorithm_instances:
            algorithm_instances = [MACDCrossover(12, 26, 9), RSIOversold(14, 30.0, 70.0)]
            weights_list = [0.5, 0.5]

        return AlgorithmCombiner(
            algorithms=algorithm_instances,
            weights=weights_list,
            operator=operator,  # type: ignore
            signal_threshold=threshold
        )

    def _fetch_historical_data(
        self,
        symbol: str,
        timeframe: int,
        dt_from: datetime.datetime,
        dt_to: datetime.datetime
    ) -> Optional[pd.DataFrame]:
        if not self.client.ensure_connected():
            return None

        rates = mt5.copy_rates_range(symbol, timeframe, dt_from, dt_to)
        if rates is None or len(rates) == 0:
            return None

        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        return df

    def _generate_synthetic_candles(
        self,
        symbol: str,
        dt_from: datetime.datetime,
        dt_to: datetime.datetime,
        num_candles: int = 300
    ) -> pd.DataFrame:
        np.random.seed(42)
        timestamps = pd.date_range(start=dt_from, end=dt_to, periods=num_candles)

        base_price = 1.0850 if "EUR" in symbol else (155.0 if "JPY" in symbol else 65000.0)
        returns = np.random.normal(0.0001, 0.0015, size=num_candles)
        price_series = base_price * np.exp(np.cumsum(returns))

        opens = price_series
        highs = opens * (1.0 + np.abs(np.random.normal(0, 0.001, size=num_candles)))
        lows = opens * (1.0 - np.abs(np.random.normal(0, 0.001, size=num_candles)))
        closes = price_series * (1.0 + np.random.normal(0, 0.0008, size=num_candles))

        df = pd.DataFrame({
            'time': timestamps,
            'open': opens,
            'high': np.maximum(highs, np.maximum(opens, closes)),
            'low': np.minimum(lows, np.minimum(opens, closes)),
            'close': closes,
            'tick_volume': np.random.randint(100, 1000, size=num_candles)
        })
        return df

    def _parse_date(self, date_str: Optional[str], default_days_back: int = 30) -> datetime.datetime:
        if not date_str:
            return datetime.datetime.now() - datetime.timedelta(days=default_days_back)
        try:
            return datetime.datetime.fromisoformat(date_str.replace('Z', ''))
        except Exception:
            return datetime.datetime.now() - datetime.timedelta(days=default_days_back)

    def _downsample_points(self, data: List[Dict[str, Any]], max_points: int = 150) -> List[Dict[str, Any]]:
        if len(data) <= max_points:
            return data

        step = len(data) / max_points
        indices = [int(i * step) for i in range(max_points)]
        if (len(data) - 1) not in indices:
            indices[-1] = len(data) - 1

        return [data[idx] for idx in indices]

    def _extract_candle_slice(
        self,
        dataframe: pd.DataFrame,
        entry_idx: int,
        exit_idx: int,
        pre_candles: int = 30,
        post_candles: int = 10
    ) -> Tuple[List[Dict[str, Any]], int, int]:
        total_bars = len(dataframe)
        slice_start = max(0, entry_idx - pre_candles)
        slice_end = min(total_bars, exit_idx + post_candles + 1)

        trade_df = dataframe.iloc[slice_start:slice_end]

        candle_slice = []
        for _, row in trade_df.iterrows():
            c_time = row['time']
            c_time_str = c_time.strftime('%Y-%m-%d %H:%M:%S') if isinstance(c_time, (datetime.datetime, pd.Timestamp)) else str(c_time)
            candle_slice.append({
                "timestamp": c_time_str,
                "open": round(float(row['open']), 5),
                "high": round(float(row['high']), 5),
                "low": round(float(row['low']), 5),
                "close": round(float(row['close']), 5),
                "volume": int(row.get('tick_volume', 100))
            })

        entry_slice_index = entry_idx - slice_start
        exit_slice_index = exit_idx - slice_start

        return candle_slice, entry_slice_index, exit_slice_index
