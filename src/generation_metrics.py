from __future__ import annotations

import csv
from copy import deepcopy
from pathlib import Path
from typing import Any

import pandas as pd
from sklearn.model_selection import StratifiedKFold
from tqdm import tqdm

from src.dataset import get_database_processed_dir, get_sqlite_database_path, render_table_ddls
from src.script_generator import _is_read_only_sql, _normalize_result
from src.search_metrics import (
    _dedupe_corpus_pairs,
    _filter_rows_with_scripts,
    _read_csv_rows,
)
from src.vanna_connector import initialize_vanna

LABEL_NOT_GENERATED = "Not generated"
LABEL_NOT_MATCHING_ROWS_AND_COLS = "Not matching number of rows and cols"
LABEL_NOT_MATCHING_ROWS = "Not matching number of rows"
LABEL_NOT_MATCHING_COLS = "Not matching number of columns"
LABEL_NOT_MATCHING_VALUES = "Not matching values"
LABEL_EVERYTHING_MATCHES = "Everything matches"

GENERATION_LABEL_ORDER = (
    LABEL_EVERYTHING_MATCHES,
    LABEL_NOT_MATCHING_VALUES,
    LABEL_NOT_MATCHING_COLS,
    LABEL_NOT_MATCHING_ROWS,
    LABEL_NOT_MATCHING_ROWS_AND_COLS,
    LABEL_NOT_GENERATED,
)
DIFFICULTY_ORDER = ("easy", "medium", "hard")
COMMENT_STYLES = ("inline", "yaml")
DESCRIPTION_STYLES = ("short", "business", "technical")


def run_generation_evaluation_pipeline(
    descriptions_csv_path: Path | str,
    interim_dir: Path | str,
    database_name: str,
    models: dict[str, str],
    qdrant_config: dict[str, Any] | None = None,
    openai_config: dict[str, Any] | None = None,
    db_config: dict[str, Any] | None = None,
    comment_styles: tuple[str, ...] = ("inline", "yaml"),
    description_styles: tuple[str, ...] = ("short", "business", "technical"),
    source_column: str | None = None,
    n_folds: int = 5,
    delete_collections: bool = True,
    collection_names: tuple[str, ...] = ("ddl", "sql"),
) -> list[Path]:
    """Run stratified k-fold SQL generation evaluation across models and style combos."""
    if not models:
        raise ValueError("models must contain at least one model entry.")

    descriptions_csv_path = Path(descriptions_csv_path)
    interim_dir = Path(interim_dir)
    scripts_dir = interim_dir / database_name / "scripts"
    generation_dir = interim_dir / database_name / "generation"

    rows = _read_csv_rows(descriptions_csv_path)
    filtered_rows = _filter_rows_with_scripts(rows, scripts_dir)
    if not filtered_rows:
        raise ValueError(f"No rows with SQL scripts found in {scripts_dir}.")

    saved_paths: list[Path] = []
    combo_configs = [
        (model_key, model_name, comment_style, description_style)
        for model_key, model_name in models.items()
        for comment_style in comment_styles
        for description_style in description_styles
    ]
    for model_key, model_name, comment_style, description_style in tqdm(
        combo_configs,
        desc="Generation evaluation combos",
    ):
        combo_openai_config = _openai_config_for_model(openai_config, model_name)
        combo = f"{comment_style}_{description_style}_{model_key}"
        if source_column is not None:
            combo = f"{combo}_{source_column}"
        description_column = source_column or f"query_{description_style}"
        if description_column not in filtered_rows[0]:
            raise ValueError(
                f"Column {description_column!r} was not found in {descriptions_csv_path}."
            )

        corpus_pairs = _dedupe_corpus_pairs(
            filtered_rows, description_column, scripts_dir
        )
        eval_rows = _build_eval_rows(filtered_rows, description_column)
        if len(eval_rows) < n_folds:
            raise ValueError(
                f"Not enough evaluation rows ({len(eval_rows)}) for {n_folds} folds."
            )

        scripts_subdir = generation_dir / "prediction_scripts" / combo
        results_subdir = generation_dir / "prediction_results" / combo
        scripts_subdir.mkdir(parents=True, exist_ok=True)
        results_subdir.mkdir(parents=True, exist_ok=True)

        sqlite_path = get_sqlite_database_path(
            database_name=database_name,
            comment_style=comment_style,
            comment_variant=description_style,
        )
        combo_db_config = _db_config_for_sqlite_path(db_config, sqlite_path)

        difficulties = [row["difficulty"] for row in eval_rows]
        try:
            splitter = StratifiedKFold(
                n_splits=n_folds,
                shuffle=True,
                random_state=42,
            )
            fold_splits = list(splitter.split(eval_rows, difficulties))
        except ValueError as exc:
            raise ValueError(
                f"Stratified k-fold failed for combo {combo!r} with n_folds={n_folds}. "
                "Try lowering n_folds so each difficulty class has enough samples."
            ) from exc

        for fold_index, (train_indices, test_indices) in enumerate(
            tqdm(
                fold_splits,
                desc=f"Folds ({combo})",
                leave=False,
            )
        ):
            train_uuids = {eval_rows[index]["uuid"] for index in train_indices}
            test_rows = [eval_rows[index] for index in test_indices]

            client = initialize_vanna(
                qdrant_config=qdrant_config,
                openai_config=combo_openai_config,
                db_config=combo_db_config,
            )

            if delete_collections:
                for collection_name in collection_names:
                    client.remove_collection(collection_name)

            table_ddls = render_table_ddls(
                database_name=database_name,
                comment_style=comment_style,
                comment_variant=description_style,
            )
            for ddl in tqdm(
                table_ddls,
                desc=f"Uploading DDL ({combo}, fold {fold_index + 1}/{n_folds})",
                leave=False,
            ):
                client.add_ddl(ddl)

            train_pairs = [
                (row_uuid, description, sql)
                for row_uuid, description, sql in corpus_pairs
                if row_uuid in train_uuids and description.strip()
            ]
            for row_uuid, description, sql in tqdm(
                train_pairs,
                desc=f"Uploading SQL ({combo}, fold {fold_index + 1}/{n_folds})",
                leave=False,
            ):
                client.add_question_sql(question=description, sql=sql)

            for test_row in tqdm(
                test_rows,
                desc=f"Generating SQL ({combo}, fold {fold_index + 1}/{n_folds})",
                leave=False,
            ):
                query = test_row["query"]
                row_uuid = test_row["uuid"]
                sql = client.generate_sql(query).strip()
                (scripts_subdir / f"{row_uuid}.sql").write_text(sql, encoding="utf-8")

                if not _is_read_only_sql(sql):
                    continue

                try:
                    result = client.run_sql(sql)
                except Exception:
                    continue

                if result is None or result.empty:
                    continue

                # result = _normalize_result(result)
                result.to_csv(results_subdir / f"{row_uuid}.csv", index=False)

        saved_paths.append(results_subdir)

    return saved_paths


def compute_generation_metrics(
    ground_truth_results_dir: Path | str,
    predicted_results_dirs: list[Path | str],
    descriptions_csv_path: Path | str,
    output_dir: Path | str | None = None,
) -> list[Path]:
    """Compare predicted result CSVs against ground truth and save per-combo labels."""
    ground_truth_results_dir = Path(ground_truth_results_dir)
    descriptions_csv_path = Path(descriptions_csv_path)
    predicted_results_dirs = [Path(path) for path in predicted_results_dirs]

    if not predicted_results_dirs:
        raise ValueError("predicted_results_dirs must contain at least one path.")

    if output_dir is None:
        output_dir = predicted_results_dirs[0].parent.parent / "metrics"
    else:
        output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    eval_rows = _eval_rows_with_ground_truth(
        _read_csv_rows(descriptions_csv_path),
        ground_truth_results_dir,
    )
    if not eval_rows:
        raise ValueError(
            f"No rows with ground-truth results found in {ground_truth_results_dir}."
        )

    saved_paths: list[Path] = []
    for predicted_results_dir in predicted_results_dirs:
        combo_name = predicted_results_dir.name
        metrics_rows: list[dict[str, str]] = []

        for eval_row in eval_rows:
            row_uuid = eval_row["uuid"]
            ground_truth_path = ground_truth_results_dir / f"{row_uuid}.csv"
            predicted_path = predicted_results_dir / f"{row_uuid}.csv"

            if not predicted_path.exists():
                label = LABEL_NOT_GENERATED
            else:
                ground_truth_df = pd.read_csv(ground_truth_path)
                predicted_df = pd.read_csv(predicted_path)
                # ground_truth_df = _normalize_result(pd.read_csv(ground_truth_path))
                # predicted_df = _normalize_result(pd.read_csv(predicted_path))
                label = _compare_result_label(ground_truth_df, predicted_df)

            metrics_rows.append(
                {
                    "uuid": row_uuid,
                    "difficulty": eval_row["difficulty"],
                    "label": label,
                }
            )

        metrics_path = output_dir / f"{combo_name}.csv"
        _write_metrics_label_csv(metrics_path, metrics_rows)
        saved_paths.append(metrics_path)

    return saved_paths


def combine_generation_metrics(
    generation_metrics_paths: list[Path | str],
    database_name: str,
    source_column: str | None = None,
) -> Path:
    """Combine per-combo generation label CSVs into one wide Excel file."""
    if not generation_metrics_paths:
        raise ValueError("generation_metrics_paths must contain at least one path.")

    combined_rows: list[dict[str, Any]] = []
    for metrics_path in generation_metrics_paths:
        metrics_path = Path(metrics_path)
        combo_stem = _strip_source_column_suffix(metrics_path.stem, source_column)
        comment_style, description_style, model_name = _parse_combo_from_metrics_stem(
            combo_stem
        )

        metrics_df = pd.read_csv(metrics_path)
        label_counts = _count_labels_by_difficulty(metrics_df)
        for difficulty, label_row in label_counts.iterrows():
            row = {
                "difficulty": difficulty,
                "model_name": model_name,
                "comment_style": comment_style,
                "description_style": description_style,
            }
            for label in GENERATION_LABEL_ORDER:
                row[label] = int(label_row.get(label, 0))
            combined_rows.append(row)

    combined_df = pd.DataFrame(combined_rows)
    combined_df["difficulty"] = pd.Categorical(
        combined_df["difficulty"],
        categories=list(DIFFICULTY_ORDER),
        ordered=True,
    )
    combined_df = combined_df.sort_values(
        ["difficulty", "model_name", "comment_style", "description_style"]
    )
    combined_df = combined_df.set_index(
        ["difficulty", "model_name", "comment_style", "description_style"]
    )
    combined_df = combined_df.reindex(columns=list(GENERATION_LABEL_ORDER), fill_value=0)
    combined_df = combined_df.astype(int)

    output_suffix = "rewritten" if source_column is None else source_column
    output_dir = get_database_processed_dir(database_name) / "metrics"
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"combined_generation_{output_suffix}.xlsx"
    combined_df.to_excel(output_path)
    return output_path


def _build_eval_rows(
    rows: list[dict[str, str]],
    description_column: str,
) -> list[dict[str, str]]:
    seen_uuids: set[str] = set()
    eval_rows: list[dict[str, str]] = []

    for row in rows:
        row_uuid = row["uuid"]
        if row_uuid in seen_uuids:
            continue
        seen_uuids.add(row_uuid)
        eval_rows.append(
            {
                "uuid": row_uuid,
                "query": row[description_column].strip(),
                "difficulty": row["difficulty"],
            }
        )

    return eval_rows


def _eval_rows_with_ground_truth(
    rows: list[dict[str, str]],
    ground_truth_results_dir: Path,
) -> list[dict[str, str]]:
    seen_uuids: set[str] = set()
    eval_rows: list[dict[str, str]] = []

    for row in rows:
        row_uuid = row["uuid"]
        if row_uuid in seen_uuids:
            continue
        if not (ground_truth_results_dir / f"{row_uuid}.csv").exists():
            continue
        seen_uuids.add(row_uuid)
        eval_rows.append(
            {
                "uuid": row_uuid,
                "difficulty": row["difficulty"],
            }
        )

    return eval_rows


def _openai_config_for_model(
    openai_config: dict[str, Any] | None,
    model_name: str,
) -> dict[str, Any] | None:
    if openai_config is None:
        return {"model": model_name}

    combo_openai_config = deepcopy(openai_config)
    combo_openai_config["model"] = model_name
    return combo_openai_config


def _db_config_for_sqlite_path(
    db_config: dict[str, Any] | None,
    sqlite_path: Path,
) -> dict[str, Any] | None:
    if db_config is None:
        return None

    combo_db_config = deepcopy(db_config)
    params = combo_db_config.setdefault("params", {})
    if not isinstance(params, dict):
        raise TypeError("db_config['params'] must be a dictionary.")
    params["url"] = str(sqlite_path)
    combo_db_config["type"] = combo_db_config.get("type", "sqlite")
    return combo_db_config


def _compare_result_label(ground_truth_df: pd.DataFrame, predicted_df: pd.DataFrame) -> str:
    gt_rows, gt_cols = ground_truth_df.shape
    pred_rows, pred_cols = predicted_df.shape
    rows_match = gt_rows == pred_rows
    cols_match = gt_cols == pred_cols

    if not rows_match and not cols_match:
        return LABEL_NOT_MATCHING_ROWS_AND_COLS
    if not rows_match:
        return LABEL_NOT_MATCHING_ROWS
    if not cols_match:
        return LABEL_NOT_MATCHING_COLS

    if _columns_match_by_values(predicted_df, ground_truth_df):
        return LABEL_EVERYTHING_MATCHES
    return LABEL_NOT_MATCHING_VALUES


def _columns_match_by_values(
    predicted_df: pd.DataFrame,
    ground_truth_df: pd.DataFrame,
) -> bool:
    predicted_values = predicted_df.astype(str)
    ground_truth_values = ground_truth_df.astype(str)
    used_ground_truth_columns: set[str] = set()

    for predicted_column in predicted_values.columns:
        predicted_series = predicted_values[predicted_column]
        matched = False
        for ground_truth_column in ground_truth_values.columns:
            if ground_truth_column in used_ground_truth_columns:
                continue
            if predicted_series.equals(ground_truth_values[ground_truth_column]):
                used_ground_truth_columns.add(ground_truth_column)
                matched = True
                break
        if not matched:
            return False
    return True


def _write_metrics_label_csv(path: Path, rows: list[dict[str, str]]) -> None:
    fieldnames = ["uuid", "difficulty", "label"]
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _strip_source_column_suffix(stem: str, source_column: str | None) -> str:
    if source_column is None:
        return stem
    suffix = f"_{source_column}"
    if stem.endswith(suffix):
        return stem[: -len(suffix)]
    return stem


def _parse_combo_from_metrics_stem(stem: str) -> tuple[str, str, str]:
    parts = stem.split("_")
    if len(parts) < 3:
        raise ValueError(
            f"Could not parse combo from metrics filename stem {stem!r}. "
            "Expected format: {{comment_style}}_{{description_style}}_{{model_name}}."
        )

    comment_style = parts[0]
    description_style = parts[1]
    model_name = "_".join(parts[2:])

    if comment_style not in COMMENT_STYLES:
        raise ValueError(
            f"Unknown comment_style={comment_style!r} in {stem!r}. "
            f"Supported: {', '.join(COMMENT_STYLES)}."
        )
    if description_style not in DESCRIPTION_STYLES:
        raise ValueError(
            f"Unknown description_style={description_style!r} in {stem!r}. "
            f"Supported: {', '.join(DESCRIPTION_STYLES)}."
        )
    return comment_style, description_style, model_name


def _count_labels_by_difficulty(metrics_df: pd.DataFrame) -> pd.DataFrame:
    if "difficulty" not in metrics_df.columns or "label" not in metrics_df.columns:
        raise ValueError("Metrics CSV must contain 'difficulty' and 'label' columns.")

    label_counts = (
        metrics_df.groupby(["difficulty", "label"]).size().unstack(fill_value=0)
    )
    for label in GENERATION_LABEL_ORDER:
        if label not in label_counts.columns:
            label_counts[label] = 0
    return label_counts[list(GENERATION_LABEL_ORDER)]
