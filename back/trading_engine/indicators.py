from typing import Dict, Any
import pandas as pd

from .algorithms import (
    RSIIndicator,
    StochasticIndicator,
    MACDIndicator,
    BollingerBandsIndicator,
)


class WeightedCombiner:
    """
    Backwards-compatible wrapper accepting {indicator: weight_float} dictionary.
    """

    def __init__(self, weights_dict: Dict[Any, float]) -> None:
        total_weight = sum(weights_dict.values())
        if abs(total_weight - 1.0) > 1e-4:
            raise ValueError(f"Total weights must equal 1.0, got {total_weight}")

        self.algorithms = list(weights_dict.keys())
        self.weights = list(weights_dict.values())

    def evaluate(self, dataframe: pd.DataFrame) -> pd.Series:
        series_list = []
        for alg, w in zip(self.algorithms, self.weights):
            if hasattr(alg, 'calculate_series'):
                s = alg.calculate_series(dataframe)
            else:
                res = alg.evaluate(dataframe)
                s = res if isinstance(res, pd.Series) else pd.Series(res, index=dataframe.index)
            series_list.append(s * float(w))

        combined = sum(series_list)
        return pd.Series(combined, index=dataframe.index if dataframe is not None else None).clip(-1.0, 1.0)


__all__ = [
    "RSIIndicator",
    "StochasticIndicator",
    "MACDIndicator",
    "BollingerBandsIndicator",
    "WeightedCombiner",
]
