import json
import logging
import datetime
from typing import Dict, Any
import numpy as np
import pandas as pd
import MetaTrader5 as mt5
from django.http import JsonResponse, HttpRequest
from django.views.decorators.csrf import csrf_exempt

from ..models import StrategyConfig, StrategyInstance, TradeDeal
from ..infrastructure.mt5 import MT5Client, InstanceManager, BacktestEngine, run_execution_cycle
from ..algorithms import RSIIndicator, StochasticIndicator, MACDIndicator, BollingerBandsIndicator, AlgorithmCombiner
from ..strategies import SimpleBuyInStrategy, SwingExtremaBuyInStrategy

logger = logging.getLogger(__name__)


def status_view(request: HttpRequest) -> JsonResponse:
    """
    Returns live account balance, equity, server state, and active worker statuses.
    """
    client = MT5Client()
    connected = client.ensure_connected()
    account_info = client.get_account_info() if connected else None

    manager = InstanceManager()
    active_instances = manager.list_all_instances()

    return JsonResponse({
        "status": "online" if connected else "offline",
        "account": account_info,
        "active_instances_count": len(active_instances),
        "instances": active_instances
    })


@csrf_exempt
def execute_cycle_view(request: HttpRequest) -> JsonResponse:
    """
    Triggers an immediate execution cycle for a given symbol and strategy config.
    """
    if request.method != "POST":
        return JsonResponse({"error": "Method not allowed"}, status=405)

    try:
        body = json.loads(request.body.decode('utf-8')) if request.body else {}
        symbol = body.get('symbol', 'EURUSD')
        timeframe = int(body.get('timeframe', 5))
        risk_percentage = float(body.get('risk_percentage', 1.0))
        sl_tp_ratio = float(body.get('sl_tp_ratio', 2.0))
        signal_threshold = float(body.get('signal_threshold', 0.5))
        max_active_positions = int(body.get('max_active_positions', 1))

        summary = run_execution_cycle(
            symbol=symbol,
            timeframe=timeframe,
            risk_percentage=risk_percentage,
            sl_tp_ratio=sl_tp_ratio,
            signal_threshold=signal_threshold,
            max_active_positions=max_active_positions
        )
        return JsonResponse({"status": "success", "summary": summary})
    except Exception as e:
        logger.error("Error executing cycle view: %s", e)
        return JsonResponse({"error": str(e)}, status=400)


@csrf_exempt
def instances_view(request: HttpRequest) -> JsonResponse:
    """
    Lists running background worker instances or deploys a new instance via POST.
    """
    manager = InstanceManager()

    if request.method == "GET":
        instances = manager.list_all_instances()
        return JsonResponse({"instances": instances})

    elif request.method == "POST":
        try:
            body = json.loads(request.body.decode('utf-8'))
            name = body.get('name', 'Strategy Worker')
            symbol = body.get('symbol', 'EURUSD')
            timeframe = int(body.get('timeframe', 5))
            risk_percentage = float(body.get('risk_percentage', 1.0))
            sl_tp_ratio = float(body.get('sl_tp_ratio', 2.0))
            operator = body.get('operator', 'WEIGHTED')
            signal_threshold = float(body.get('signal_threshold', 0.5))
            max_active_positions = int(body.get('max_active_positions', 1))
            indicators = body.get('indicators', [])

            worker = manager.create_and_start_instance(
                name=name,
                symbol=symbol,
                timeframe=timeframe,
                risk_percentage=risk_percentage,
                sl_tp_ratio=sl_tp_ratio,
                operator=operator,
                signal_threshold=signal_threshold,
                max_active_positions=max_active_positions,
                indicators=indicators
            )

            StrategyInstance.objects.create(
                name=name,
                symbol=symbol,
                timeframe=timeframe,
                risk_percentage=risk_percentage,
                sl_tp_ratio=sl_tp_ratio,
                max_active_positions=max_active_positions,
                operator=operator,
                signal_threshold=signal_threshold,
                is_running=True,
                config_json={"indicators": indicators}
            )

            return JsonResponse({
                "status": "started",
                "instance_id": worker.instance_id,
                "symbol": symbol
            }, status=201)

        except Exception as e:
            logger.error("Error deploying instance: %s", e)
            return JsonResponse({"error": str(e)}, status=400)


@csrf_exempt
def stop_instance_view(request: HttpRequest, instance_id: str) -> JsonResponse:
    """
    Stops a running background worker instance by ID.
    """
    if request.method != "POST":
        return JsonResponse({"error": "Method not allowed"}, status=405)

    manager = InstanceManager()
    stopped = manager.stop_instance(instance_id)

    StrategyInstance.objects.filter(id=instance_id).update(is_running=False)

    if stopped:
        return JsonResponse({"status": "stopped", "instance_id": instance_id})
    return JsonResponse({"status": "not_found", "instance_id": instance_id}, status=404)


@csrf_exempt
def backtest_view(request: HttpRequest) -> JsonResponse:
    """
    Executes historical backtest simulation over date range.
    """
    if request.method != "POST":
        return JsonResponse({"error": "Method not allowed"}, status=405)

    try:
        body = json.loads(request.body.decode('utf-8'))
        algorithm_config = body.get('algorithm_config', {})
        buy_in_config = body.get('buy_in_config', {})
        symbol = body.get('symbol', 'EURUSD')
        date_from = body.get('date_from')
        date_to = body.get('date_to')
        initial_balance = float(body.get('initial_balance', 10000.0))
        timeframe = int(body.get('timeframe', 5))

        engine = BacktestEngine()
        report = engine.run(
            algorithm_config=algorithm_config,
            buy_in_config=buy_in_config,
            symbol=symbol,
            date_from=date_from,
            date_to=date_to,
            initial_balance=initial_balance,
            timeframe=timeframe
        )

        return JsonResponse({"status": "success", "report": report}, status=200)

    except Exception as e:
        logger.error("Backtest execution error: %s", e)
        return JsonResponse({"error": str(e)}, status=400)


@csrf_exempt
def configs_view(request: HttpRequest) -> JsonResponse:
    """
    Lists active strategy configurations, creates/updates via POST, or deletes via DELETE.
    """
    if request.method == "GET":
        configs = list(StrategyConfig.objects.filter(is_active=True).values())
        return JsonResponse({"configs": configs})

    elif request.method == "POST":
        try:
            body = json.loads(request.body.decode('utf-8'))
            name = body['name']

            config_json = body.get('config_json', {})
            if not isinstance(config_json, dict):
                config_json = {}

            risk_pct = float(body.get('risk_percentage', config_json.get('risk_percentage', 1.0)))
            sl_tp = float(body.get('sl_tp_ratio', config_json.get('sl_tp_ratio', 2.0)))
            max_pos = int(body.get('max_active_positions', config_json.get('max_active_positions', 1)))
            op = body.get('operator', config_json.get('operator', 'WEIGHTED'))
            thresh = float(body.get('signal_threshold', config_json.get('threshold', 0.5)))
            buyin_method = body.get('buy_in_method', config_json.get('buyInMethod', 'Simple Buy-in'))

            snapshot_json = {
                'indicators': config_json.get('indicators', body.get('indicators', [])),
                'operator': op,
                'threshold': thresh,
                'signal_threshold': thresh,
                'buyInMethod': buyin_method,
                'buy_in_method': buyin_method,
                'risk_percentage': risk_pct,
                'sl_tp_ratio': sl_tp,
                'max_active_positions': max_pos,
            }

            config, created = StrategyConfig.objects.update_or_create(
                name=name,
                defaults={
                    'symbol': body.get('symbol', 'EURUSD'),
                    'timeframe': int(body.get('timeframe', 5)),
                    'risk_percentage': risk_pct,
                    'sl_tp_ratio': sl_tp,
                    'max_active_positions': max_pos,
                    'operator': op,
                    'signal_threshold': thresh,
                    'config_json': snapshot_json,
                    'is_active': True,
                }
            )
            return JsonResponse({"status": "created" if created else "updated", "id": config.id}, status=201 if created else 200)
        except Exception as e:
            return JsonResponse({"error": str(e)}, status=400)

    elif request.method == "DELETE":
        try:
            body = json.loads(request.body.decode('utf-8')) if request.body else {}
            config_id = body.get('id')
            name = body.get('name')

            if config_id:
                StrategyConfig.objects.filter(id=config_id).update(is_active=False)
            elif name:
                StrategyConfig.objects.filter(name=name).update(is_active=False)
            return JsonResponse({"status": "deleted"})
        except Exception as e:
            return JsonResponse({"error": str(e)}, status=400)


@csrf_exempt
def history_view(request: HttpRequest) -> JsonResponse:
    """
    Returns historical MT5 executed positions consolidated into single round-trip trades.
    """
    client = MT5Client()

    if client.ensure_connected():
        mt5_history = mt5.history_deals_get(
            datetime.datetime.now() - datetime.timedelta(days=30),
            datetime.datetime.now()
        )
        if mt5_history is not None:
            positions_map: Dict[int, Dict[str, Any]] = {}
            unGrouped_deals: List[Dict[str, Any]] = []

            for deal in mt5_history:
                # Exclude deposit / balance deals
                if getattr(deal, 'type', None) not in (0, 1):
                    continue
                comment_str = str(getattr(deal, 'comment', '')).lower()
                if 'deposit' in comment_str or 'balance' in comment_str:
                    continue

                pos_id = getattr(deal, 'position_id', getattr(deal, 'order', 0))
                entry_type = getattr(deal, 'entry', None)

                deal_dict = {
                    "ticket": deal.ticket,
                    "order": deal.order,
                    "position_id": pos_id,
                    "symbol": deal.symbol,
                    "type": "BUY" if deal.type == 0 else "SELL",
                    "entry": entry_type,
                    "volume": round(float(deal.volume), 2),
                    "price": round(float(deal.price), 5),
                    "profit": round(float(deal.profit), 2),
                    "comment": deal.comment,
                    "time": datetime.datetime.fromtimestamp(deal.time).strftime('%Y-%m-%d %H:%M:%S')
                }

                if pos_id and pos_id > 0:
                    if pos_id not in positions_map:
                        positions_map[pos_id] = {
                            "ticket": pos_id,
                            "position_id": pos_id,
                            "symbol": deal.symbol,
                            "type": "BUY" if deal.type == 0 else "SELL",
                            "volume": round(float(deal.volume), 2),
                            "entry_price": round(float(deal.price), 5),
                            "price": round(float(deal.price), 5),
                            "exit_price": round(float(deal.price), 5),
                            "profit": round(float(deal.profit), 2),
                            "comment": deal.comment,
                            "time": datetime.datetime.fromtimestamp(deal.time).strftime('%Y-%m-%d %H:%M:%S')
                        }
                    else:
                        p_info = positions_map[pos_id]
                        if entry_type == 1 or abs(deal.profit) > 0:
                            p_info["exit_price"] = round(float(deal.price), 5)
                            p_info["profit"] = round(float(deal.profit), 2)
                            p_info["time"] = datetime.datetime.fromtimestamp(deal.time).strftime('%Y-%m-%d %H:%M:%S')
                            if deal.comment:
                                p_info["comment"] = deal.comment
                        else:
                            p_info["entry_price"] = round(float(deal.price), 5)
                            p_info["price"] = round(float(deal.price), 5)
                            p_info["type"] = "BUY" if deal.type == 0 else "SELL"
                else:
                    unGrouped_deals.append(deal_dict)

            trades_list = list(positions_map.values()) + unGrouped_deals
            trades_list.sort(key=lambda x: str(x.get('time', '')), reverse=True)
            return JsonResponse({"history": trades_list[:50]})

    db_history = list(TradeDeal.objects.order_by('-time')[:50].values())
    return JsonResponse({"history": db_history})


@csrf_exempt
def evaluate_indicator_view(request: HttpRequest) -> JsonResponse:
    """
    Evaluates specified indicator or combiner against symbol history and returns series + score.
    """
    if request.method != "POST":
        return JsonResponse({"error": "Method not allowed"}, status=405)

    try:
        body = json.loads(request.body.decode('utf-8'))
        indicator_id = body.get('indicator_id', 'rsi')
        symbol = body.get('symbol', 'EURUSD')
        timeframe = int(body.get('timeframe', 5))
        params = body.get('params', {})
        indicators_list = body.get('indicators', [])

        client = MT5Client()
        rates_df = client.copy_rates_from_pos(symbol=symbol, timeframe=timeframe, count=100)

        if rates_df is None or rates_df.empty:
            np.random.seed(42)
            timestamps = pd.date_range(end=pd.Timestamp.now(), periods=100, freq='5min')
            close_prices = 1.0850 + np.cumsum(np.random.normal(0, 0.0002, 100))
            rates_df = pd.DataFrame({'time': timestamps, 'open': close_prices, 'high': close_prices + 0.0003, 'low': close_prices - 0.0003, 'close': close_prices})

        if indicator_id == "rsi":
            obj = RSIIndicator(period=int(params.get("period", 14)))
            series = obj.calculate_series(rates_df)
        elif indicator_id == "stochastic":
            obj = StochasticIndicator(k_period=int(params.get("k_period", 14)), d_period=int(params.get("d_period", 3)))
            series = obj.calculate_series(rates_df)
        elif indicator_id == "macd":
            obj = MACDIndicator(fast=int(params.get("fast", 12)), slow=int(params.get("slow", 26)), signal=int(params.get("signal", 9)), z_window=int(params.get("z_window", 100)))
            series = obj.calculate_series(rates_df)
        elif indicator_id == "bollinger":
            obj = BollingerBandsIndicator(period=int(params.get("period", 20)), std_dev=float(params.get("std_dev", 2.0)))
            series = obj.calculate_series(rates_df)
        elif indicator_id == "weighted_combiner":
            series_list = []
            for item in indicators_list:
                ind_id = item.get("id", "rsi")
                p = item.get("params", {})
                w = float(item.get("weight", 0.5))
                if ind_id == "rsi":
                    ind_obj = RSIIndicator(period=int(p.get("period", 14)))
                elif ind_id == "stochastic":
                    ind_obj = StochasticIndicator(k_period=int(p.get("k_period", 14)), d_period=int(p.get("d_period", 3)))
                elif ind_id == "macd":
                    ind_obj = MACDIndicator(fast=int(p.get("fast", 12)), slow=int(p.get("slow", 26)), signal=int(p.get("signal", 9)), z_window=int(p.get("z_window", 100)))
                elif ind_id == "bollinger":
                    ind_obj = BollingerBandsIndicator(period=int(p.get("period", 20)), std_dev=float(p.get("std_dev", 2.0)))
                else:
                    continue

                ind_series = ind_obj.calculate_series(rates_df)
                series_list.append((ind_series, w))

            if not series_list:
                rsi_obj = RSIIndicator(14)
                series_list = [(rsi_obj.calculate_series(rates_df), 1.0)]

            total_weight = sum(w for _, w in series_list) if sum(w for _, w in series_list) > 0 else 1.0
            combined = sum(s * w for s, w in series_list) / total_weight
            series = combined.clip(-1.0, 1.0)
        else:
            return JsonResponse({"error": f"Unknown indicator {indicator_id}"}, status=400)

        if isinstance(series, pd.Series):
            series_list = series.tolist()
        elif isinstance(series, (list, tuple)):
            series_list = list(series)
        else:
            series_list = [float(series)]

        latest_val = float(series_list[-1]) if series_list else 0.0
        bias = "BULLISH (+1.0)" if latest_val > 0.2 else ("BEARISH (-1.0)" if latest_val < -0.2 else "NEUTRAL (0.0)")

        return JsonResponse({
            "indicator_id": indicator_id,
            "symbol": symbol,
            "latest_value": latest_val,
            "bias": bias,
            "series": series_list[-50:]
        })

    except Exception as e:
        logger.error("Error evaluating indicator view: %s", e)
        return JsonResponse({"error": str(e)}, status=400)
