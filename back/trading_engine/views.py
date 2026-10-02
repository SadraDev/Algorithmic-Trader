import json
from django.http import JsonResponse, HttpRequest
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from .mt5_client import MT5Client
from .executor import execute_trading_cycle, InstanceManager
from .models import StrategyConfig, TradeLog
from .indicators import (
    RSIIndicator,
    StochasticIndicator,
    MACDIndicator,
    BollingerBandsIndicator,
    WeightedCombiner
)


def status_view(request: HttpRequest) -> JsonResponse:
    """
    Returns current MetaTrader 5 terminal connection status and live account details.
    """
    client = MT5Client()
    connected = client.ensure_connected()
    acc_info = client.account_info() if connected else None

    data = {
        "connected": connected,
        "account": {
            "login": getattr(acc_info, 'login', None),
            "server": getattr(acc_info, 'server', None),
            "company": getattr(acc_info, 'company', None),
            "balance": getattr(acc_info, 'balance', None),
            "equity": getattr(acc_info, 'equity', None),
            "margin": getattr(acc_info, 'margin', None),
            "free_margin": getattr(acc_info, 'margin_free', None),
            "profit": getattr(acc_info, 'profit', None),
            "leverage": getattr(acc_info, 'leverage', None),
            "currency": getattr(acc_info, 'currency', None),
            "trade_allowed": getattr(acc_info, 'trade_allowed', True),
        } if acc_info else None
    }
    return JsonResponse(data)


@csrf_exempt
@require_http_methods(["POST"])
def execute_cycle_view(request: HttpRequest) -> JsonResponse:
    """
    Triggers a manual trading execution cycle via POST request and logs execution to database.
    """
    try:
        body = json.loads(request.body.decode('utf-8')) if request.body else {}
    except Exception:
        return JsonResponse({"error": "Invalid JSON body"}, status=400)

    symbol = body.get("symbol", "EURUSD")
    timeframe = int(body.get("timeframe", 5))
    risk_percentage = float(body.get("risk_percentage", 1.0))
    sl_tp_ratio = float(body.get("sl_tp_ratio", 2.0))
    operator = body.get("operator", "OR")
    signal_threshold = float(body.get("signal_threshold", 0.5))
    max_active_positions = int(body.get("max_active_positions", 1))
    indicators = body.get("indicators", [])

    summary = execute_trading_cycle(
        symbol=symbol,
        timeframe=timeframe,
        risk_percentage=risk_percentage,
        sl_tp_ratio=sl_tp_ratio,
        operator=operator,
        signal_threshold=signal_threshold,
        max_active_positions=max_active_positions,
        indicators=indicators
    )

    # Log cycle result in database
    signal = summary.get("signal", 0)
    executed = summary.get("order_executed", False)
    order_res = summary.get("order_result", {})

    action = 'SIGNAL_SKIP'
    if executed:
        action = 'OPEN_BUY' if signal == 1 else ('OPEN_SELL' if signal == -1 else 'SIGNAL_SKIP')

    TradeLog.objects.create(
        symbol=symbol,
        action=action,
        signal=signal,
        price=order_res.get("price"),
        volume=order_res.get("volume"),
        ticket=order_res.get("deal"),
        comment=f"Manual execution cycle via API: {summary.get('errors', [])}"
    )

    return JsonResponse(summary)


# =============================================================================
# BACKGROUND MULTI-INSTANCE ENDPOINTS
# =============================================================================

@csrf_exempt
def instances_view(request: HttpRequest) -> JsonResponse:
    """
    GET: Lists all active running algorithm instances.
    POST: Spawns a new background worker instance for chosen symbol/timeframe.
    """
    manager = InstanceManager()

    if request.method == "GET":
        return JsonResponse({"instances": manager.list_instances()})

    elif request.method == "POST":
        try:
            body = json.loads(request.body.decode('utf-8')) if request.body else {}
            name = body.get("name", "Strategy Instance")
            symbol = body.get("symbol", "EURUSD")
            timeframe = int(body.get("timeframe", 5))
            risk_percentage = float(body.get("risk_percentage", 1.0))
            sl_tp_ratio = float(body.get("sl_tp_ratio", 2.0))
            operator = body.get("operator", "WEIGHTED")
            signal_threshold = float(body.get("signal_threshold", 0.5))
            max_active_positions = int(body.get("max_active_positions", 1))
            indicators = body.get("indicators", [])

            inst_data = manager.start_instance(
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
            return JsonResponse({"status": "started", "instance": inst_data}, status=201)
        except Exception as e:
            return JsonResponse({"error": str(e)}, status=400)

    return JsonResponse({"error": "Method not allowed"}, status=405)


@csrf_exempt
@require_http_methods(["POST"])
def instance_pause_view(request: HttpRequest, instance_id: str) -> JsonResponse:
    """
    Pauses or resumes an active algorithm instance.
    """
    manager = InstanceManager()
    res = manager.pause_instance(instance_id)
    if res:
        return JsonResponse({"status": "updated", "instance": res})
    return JsonResponse({"error": "Instance not found"}, status=404)


@csrf_exempt
@require_http_methods(["POST", "DELETE"])
def instance_stop_view(request: HttpRequest, instance_id: str) -> JsonResponse:
    """
    Stops and terminates a running background algorithm instance.
    """
    manager = InstanceManager()
    success = manager.stop_instance(instance_id)
    if success:
        return JsonResponse({"status": "stopped", "instance_id": instance_id})
    return JsonResponse({"error": "Instance not found"}, status=404)


# =============================================================================
# REAL MT5 HISTORY DEALS ENDPOINT
# =============================================================================

def history_deals_view(request: HttpRequest) -> JsonResponse:
    """
    Fetches real closed trades and deal executions directly from MetaTrader 5.
    """
    client = MT5Client()
    deals = client.get_history_deals()
    return JsonResponse({"history_deals": deals})


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

            config, created = StrategyConfig.objects.update_or_create(
                name=name,
                defaults={
                    'symbol': body.get('symbol', 'EURUSD'),
                    'timeframe': int(body.get('timeframe', 5)),
                    'risk_percentage': float(body.get('risk_percentage', 1.0)),
                    'sl_tp_ratio': float(body.get('sl_tp_ratio', 2.0)),
                    'operator': body.get('operator', 'WEIGHTED'),
                    'signal_threshold': float(body.get('signal_threshold', 0.5)),
                    'config_json': body.get('config_json', {}),
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
                StrategyConfig.objects.filter(id=config_id).delete()
            elif name:
                StrategyConfig.objects.filter(name=name).delete()
            else:
                return JsonResponse({"error": "Must provide 'id' or 'name'"}, status=400)

            return JsonResponse({"status": "deleted"})
        except Exception as e:
            return JsonResponse({"error": str(e)}, status=400)

    return JsonResponse({"error": "Method not allowed"}, status=405)


def logs_view(request: HttpRequest) -> JsonResponse:
    """
    Retrieves recent trade execution logs.
    """
    logs = list(TradeLog.objects.all().values()[:50])
    return JsonResponse({"logs": logs})


def indicators_list_view(request: HttpRequest) -> JsonResponse:
    """
    Returns list of available default normalized indicators.
    """
    indicators = [
        {
            "id": "rsi",
            "name": "RSI Indicator",
            "description": "Standard RSI transformed linearly into [-1.0, 1.0].",
            "parameters": {"period": 14, "timeframe": "M5"}
        },
        {
            "id": "stochastic",
            "name": "Stochastic Oscillator",
            "description": "%K line transformed linearly into [-1.0, 1.0].",
            "parameters": {"k_period": 14, "d_period": 3, "timeframe": "M5"}
        },
        {
            "id": "macd",
            "name": "MACD Z-Score",
            "description": "MACD Histogram normalized via Z-score and squashed via np.tanh().",
            "parameters": {"fast": 12, "slow": 26, "signal": 9, "z_window": 100, "timeframe": "M5"}
        },
        {
            "id": "bollinger",
            "name": "Bollinger Bands Deviation",
            "description": "Price distance from bands squashed via np.tanh().",
            "parameters": {"period": 20, "std_dev": 2.0, "timeframe": "M5"}
        }
    ]
    return JsonResponse({"indicators": indicators})


TIMEFRAME_MAP = {
    "M1": 1,
    "M5": 5,
    "M15": 15,
    "M30": 30,
    "H1": 60,
    "H4": 240,
    "D1": 1440,
}


@csrf_exempt
@require_http_methods(["POST"])
def indicators_evaluate_view(request: HttpRequest) -> JsonResponse:
    """
    Evaluates selected indicator or dynamic multi-indicator list against live MT5 rate data.
    """
    try:
        body = json.loads(request.body.decode('utf-8')) if request.body else {}
    except Exception:
        return JsonResponse({"error": "Invalid JSON body"}, status=400)

    indicator_id = body.get("indicator_id", "rsi")
    symbol = body.get("symbol", "EURUSD")
    tf_input = body.get("timeframe", 5)

    if isinstance(tf_input, str):
        timeframe = TIMEFRAME_MAP.get(tf_input.upper(), 5)
    else:
        timeframe = int(tf_input)

    client = MT5Client()
    try:
        df = client.copy_rates_from_pos(symbol, timeframe, start_pos=0, count=100)
    except Exception as e:
        return JsonResponse({"error": f"Failed to fetch rates for {symbol}: {e}"}, status=400)

    if df is None or df.empty:
        return JsonResponse({"error": f"No market rate data available for {symbol}"}, status=400)

    # Dynamic multi-indicator list handling
    indicators_data = body.get("indicators", [])

    if indicator_id == "weighted_combiner" or indicators_data:
        if not indicators_data:
            indicators_data = [
                {"id": "rsi", "params": {"period": 14}, "weight": 0.4},
                {"id": "macd", "params": {"fast": 12, "slow": 26, "signal": 9, "z_window": 100}, "weight": 0.6}
            ]

        weighted_dict = {}
        for ind_item in indicators_data:
            ind_type = ind_item.get("id", "rsi")
            params = ind_item.get("params", {})
            w = float(ind_item.get("weight", 0.5))

            if ind_type == "rsi":
                obj = RSIIndicator(period=int(params.get("period", 14)))
            elif ind_type == "stochastic":
                obj = StochasticIndicator(
                    k_period=int(params.get("k_period", 14)),
                    d_period=int(params.get("d_period", 3))
                )
            elif ind_type == "macd":
                obj = MACDIndicator(
                    fast=int(params.get("fast", 12)),
                    slow=int(params.get("slow", 26)),
                    signal=int(params.get("signal", 9)),
                    z_window=int(params.get("z_window", 100))
                )
            elif ind_type == "bollinger":
                obj = BollingerBandsIndicator(
                    period=int(params.get("period", 20)),
                    std_dev=float(params.get("std_dev", 2.0))
                )
            else:
                continue

            weighted_dict[obj] = w

        if not weighted_dict:
            return JsonResponse({"error": "No valid indicators provided"}, status=400)

        # Normalize weight sum to 1.0
        tot_w = sum(weighted_dict.values())
        if tot_w <= 0:
            tot_w = 1.0
        normalized_weights = {ind_obj: w / tot_w for ind_obj, w in weighted_dict.items()}

        ind = WeightedCombiner(normalized_weights)

    else:
        # Single indicator evaluation
        if indicator_id == "rsi":
            period = int(body.get("period", 14))
            ind = RSIIndicator(period=period)
        elif indicator_id == "stochastic":
            k_period = int(body.get("k_period", 14))
            d_period = int(body.get("d_period", 3))
            ind = StochasticIndicator(k_period=k_period, d_period=d_period)
        elif indicator_id == "macd":
            fast = int(body.get("fast", 12))
            slow = int(body.get("slow", 26))
            signal = int(body.get("signal", 9))
            z_window = int(body.get("z_window", 100))
            ind = MACDIndicator(fast=fast, slow=slow, signal=signal, z_window=z_window)
        elif indicator_id == "bollinger":
            period = int(body.get("period", 20))
            std_dev = float(body.get("std_dev", 2.0))
            ind = BollingerBandsIndicator(period=period, std_dev=std_dev)
        else:
            return JsonResponse({"error": f"Unknown indicator_id: {indicator_id}"}, status=400)

    series = ind.evaluate(df)
    series_list = [round(float(v), 4) for v in series.tail(20).tolist()]
    latest_val = round(float(series.iloc[-1]), 4) if len(series) > 0 else 0.0

    if latest_val > 0.2:
        bias = f"BULLISH (+{latest_val:.2f})"
    elif latest_val < -0.2:
        bias = f"BEARISH ({latest_val:.2f})"
    else:
        bias = f"NEUTRAL ({latest_val:.2f})"

    return JsonResponse({
        "indicator_id": indicator_id,
        "symbol": symbol,
        "latest_value": latest_val,
        "bias": bias,
        "series": series_list
    })
