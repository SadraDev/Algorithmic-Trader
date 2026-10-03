import logging
from typing import List, Literal, Sequence, Optional
import pandas as pd

from .base import BaseAlgorithm

logger = logging.getLogger(__name__)


class AlgorithmCombiner(BaseAlgorithm):
    """
    Consolidates multiple indicator signals into a single trade signal (-1, 0, 1) based on
    four distinct logic gates (WEIGHTED, AND, OR, XOR) and a configurable threshold n.
    """

    def __init__(
        self,
        algorithms: Sequence[BaseAlgorithm],
        weights: Optional[Sequence[float]] = None,
        operator: Literal['WEIGHTED', 'AND', 'OR', 'XOR'] = 'WEIGHTED',
        signal_threshold: float = 0.5
    ) -> None:
        if not algorithms:
            raise ValueError("At least one algorithm must be provided to AlgorithmCombiner")

        op_upper = operator.upper()
        if op_upper not in ('WEIGHTED', 'AND', 'OR', 'XOR'):
            raise ValueError(f"Operator must be 'WEIGHTED', 'AND', 'OR', or 'XOR', got '{operator}'")

        self.algorithms: List[BaseAlgorithm] = list(algorithms)
        self.weights: List[float] = list(weights) if weights and len(weights) == len(algorithms) else [1.0 / len(algorithms)] * len(algorithms)
        self.operator: Literal['WEIGHTED', 'AND', 'OR', 'XOR'] = op_upper  # type: ignore
        self.signal_threshold: float = max(0.01, min(1.0, float(signal_threshold)))

    def calculate_composite_score(self, dataframe: pd.DataFrame) -> float:
        """
        Calculates continuous composite score bounded in [-1.0, 1.0].
        """
        signals = [alg.evaluate(dataframe) for alg in self.algorithms]
        total_weight = sum(self.weights) if sum(self.weights) > 0 else 1.0
        score = sum(s * w for s, w in zip(signals, self.weights)) / total_weight
        return max(-1.0, min(1.0, float(score)))

    def evaluate(self, dataframe: pd.DataFrame) -> float:
        """
        Evaluates child indicators and processes output through logic gates against threshold n.
        """
        signals = [alg.evaluate(dataframe) for alg in self.algorithms]
        n = self.signal_threshold

        logger.debug(
            "AlgorithmCombiner gate [%s] signals: %s, weights: %s, threshold n: %.2f",
            self.operator,
            signals,
            self.weights,
            n
        )

        if self.operator == 'WEIGHTED':
            total_weight = sum(self.weights) if sum(self.weights) > 0 else 1.0
            composite_score = sum(s * w for s, w in zip(signals, self.weights)) / total_weight

            if isinstance(composite_score, pd.Series):
                return composite_score
            if composite_score >= n:
                return 1.0
            elif composite_score <= -n:
                return -1.0
            return 0.0

        elif self.operator == 'AND':
            if all(s >= n for s in signals):
                return 1.0
            elif all(s <= -n for s in signals):
                return -1.0
            return 0.0

        elif self.operator == 'OR':
            has_long = any(s >= n for s in signals)
            has_short = any(s <= -n for s in signals)

            if has_long and not has_short:
                return 1.0
            elif has_short and not has_long:
                return -1.0
            return 0.0

        elif self.operator == 'XOR':
            has_pos_breach = any(s >= n for s in signals)
            has_neg_breach = any(s <= -n for s in signals)

            if has_pos_breach and has_neg_breach:
                pos_weight = sum(w for s, w in zip(signals, self.weights) if s >= n)
                neg_weight = sum(w for s, w in zip(signals, self.weights) if s <= -n)

                if pos_weight > neg_weight:
                    return 1.0
                elif neg_weight > pos_weight:
                    return -1.0
                return 1.0

            return 0.0

        return 0.0
