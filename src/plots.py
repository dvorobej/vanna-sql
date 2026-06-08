from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

from src.generation_metrics import DIFFICULTY_ORDER, GENERATION_LABEL_ORDER
from src.search_metrics import RANKING_METRIC_NAMES

METRIC_TITLES = {
    "mrr": "MRR",
    "map_at_k": "MAP@k",
    "recall_at_k": "Recall@k",
}


def _wrap_label_after_two_words(text: str) -> str:
    words = text.split()
    if not words:
        return text
    lines = [" ".join(words[index : index + 2]) for index in range(0, len(words), 2)]
    return "\n".join(lines)


def plot_combined_generation_metrics(
    combined_metrics_path: Path | str,
    style_filters: list[tuple[str, str]],
    output_path: Path | str | None = None,
) -> list[Path]:
    """Plot combined generation metrics as grouped bar charts per difficulty."""
    combined_metrics_path = Path(combined_metrics_path)
    metrics_df = pd.read_excel(
        combined_metrics_path,
        index_col=[0, 1, 2, 3],
    )
    metrics_df.index.names = [
        "difficulty",
        "model_name",
        "comment_style",
        "description_style",
    ]

    plots_dir = combined_metrics_path.parent.parent / "plots"
    plots_dir.mkdir(parents=True, exist_ok=True)
    saved_paths: list[Path] = []

    for filter_index, (comment_style, description_style) in enumerate(style_filters):
        filtered = metrics_df[
            (metrics_df.index.get_level_values("comment_style") == comment_style)
            & (metrics_df.index.get_level_values("description_style") == description_style)
        ]
        if filtered.empty:
            raise ValueError(
                f"No rows found for comment_style={comment_style!r} and "
                f"description_style={description_style!r} in {combined_metrics_path}."
            )

        models = sorted(filtered.index.get_level_values("model_name").unique())
        difficulties = [
            difficulty
            for difficulty in DIFFICULTY_ORDER
            if difficulty in filtered.index.get_level_values("difficulty")
        ]

        if output_path is not None and len(style_filters) == 1:
            plot_path = Path(output_path)
        elif len(style_filters) == 1:
            plot_path = plots_dir / combined_metrics_path.with_suffix(".png").name
        else:
            plot_path = (
                plots_dir
                / f"{combined_metrics_path.stem}_{comment_style}_{description_style}.png"
            )

        plot_path.parent.mkdir(parents=True, exist_ok=True)
        _plot_generation_style_group(
            filtered=filtered,
            models=models,
            difficulties=difficulties,
            comment_style=comment_style,
            description_style=description_style,
            plot_path=plot_path,
        )
        saved_paths.append(plot_path)

    return saved_paths


def _plot_generation_style_group(
    filtered: pd.DataFrame,
    models: list[str],
    difficulties: list[str],
    comment_style: str,
    description_style: str,
    plot_path: Path,
) -> None:
    n_models = len(models)
    n_labels = len(GENERATION_LABEL_ORDER)
    group_gap = 1.0
    bar_width = 0.8 / max(n_models, 1)
    group_width = n_models * bar_width + group_gap

    fig, axes = plt.subplots(len(DIFFICULTY_ORDER), 1, figsize=(16, 4 * len(DIFFICULTY_ORDER)))
    if len(DIFFICULTY_ORDER) == 1:
        axes = [axes]

    for axis, difficulty in zip(axes, DIFFICULTY_ORDER):
        if difficulty not in difficulties:
            axis.set_visible(False)
            continue

        difficulty_df = filtered.xs(difficulty, level="difficulty")
        max_count = 0

        for label_index, label in enumerate(GENERATION_LABEL_ORDER):
            group_base = label_index * group_width
            for model_index, model_name in enumerate(models):
                model_rows = difficulty_df[
                    difficulty_df.index.get_level_values("model_name") == model_name
                ]
                value = int(model_rows[label].sum()) if not model_rows.empty else 0
                max_count = max(max_count, value)
                x_position = group_base + model_index * bar_width
                bar_container = axis.bar(
                    x_position,
                    value,
                    width=bar_width,
                    color=f"C{model_index}",
                )
                axis.bar_label(
                    bar_container,
                    labels=[model_name],
                    padding=2,
                    fontsize=11,
                    rotation=90,
                )

        tick_positions = [
            label_index * group_width + (n_models - 1) * bar_width / 2
            for label_index in range(n_labels)
        ]
        axis.set_xticks(tick_positions)
        wrapped_labels = [_wrap_label_after_two_words(label) for label in GENERATION_LABEL_ORDER]
        axis.set_xticklabels(wrapped_labels, rotation=0, ha="center")
        axis.set_title(difficulty)
        axis.set_ylabel("count")
        axis.set_ylim(0, max(max_count * 1.15, 1))

    fig.suptitle(f"SQL generation quality: comment style {comment_style} / description style {description_style}")
    fig.tight_layout()
    fig.savefig(plot_path, bbox_inches="tight")
    plt.close(fig)


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
            combined_metrics_path.parent.parent
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
