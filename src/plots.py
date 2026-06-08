from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

from src.search_metrics import RANKING_METRIC_NAMES

METRIC_TITLES = {
    "mrr": "MRR",
    "map_at_k": "MAP@k",
    "recall_at_k": "Recall@k",
}


def plot_combined_search_ranking_metrics(
    combined_metrics_path: Path | str,
    column_mode: str = "combined",
    k: int = 5,
    output_path: Path | str | None = None,
) -> Path:
    """Plot combined search ranking metrics as bar charts, one subplot per metric."""
    combined_metrics_path = Path(combined_metrics_path)
    metrics_df = pd.read_excel(combined_metrics_path, index_col=0)

    missing_metrics = [
        metric for metric in RANKING_METRIC_NAMES if metric not in metrics_df.columns
    ]
    if missing_metrics:
        raise ValueError(
            f"Missing metrics {missing_metrics} in {combined_metrics_path}."
        )

    if output_path is None:
        output_path = (
            combined_metrics_path.parent
            / "plots"
            / combined_metrics_path.with_suffix(".png").name
        )
    else:
        output_path = Path(output_path)

    output_path.parent.mkdir(parents=True, exist_ok=True)

    labels = [str(label) for label in metrics_df.index]
    fig, axes = plt.subplots(1, len(RANKING_METRIC_NAMES), figsize=(15, 6))

    for axis, metric_name in zip(axes, RANKING_METRIC_NAMES):
        values = metrics_df[metric_name].tolist()
        axis.bar(labels, values)
        axis.set_title(METRIC_TITLES[metric_name])
        axis.set_ylim(0, 1)
        axis.tick_params(axis="x", rotation=45)
    fig.suptitle(f"{column_mode.capitalize()} Search Ranking Metrics @k={k}")

    fig.tight_layout()
    fig.savefig(output_path, bbox_inches="tight")
    plt.close(fig)
    return output_path
