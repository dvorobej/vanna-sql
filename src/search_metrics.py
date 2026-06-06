from __future__ import annotations

import csv
import re
from pathlib import Path
from typing import Any

from tqdm import tqdm

from src.dataset import render_table_ddls
from src.vanna_connector import VannaClient, initialize_vanna

DEFAULT_SEARCH_QUERY_COLUMNS = [
    "query_short_related",
    "query_business_related",
    "query_technical_related",
]


def reciprocal_rank(relevant_id: str, predicted_ids: list[str]) -> float:
    for rank, predicted_id in enumerate(predicted_ids, start=1):
        if predicted_id == relevant_id:
            return 1.0 / rank
    return 0.0


def average_precision_at_k(relevant_id: str, predicted_ids: list[str], k: int) -> float:
    for rank, predicted_id in enumerate(predicted_ids[:k], start=1):
        if predicted_id == relevant_id:
            return 1.0 / rank
    return 0.0


def recall_at_k(relevant_id: str, predicted_ids: list[str], k: int) -> float:
    return 1.0 if relevant_id in predicted_ids[:k] else 0.0


def combine_predicted_ids(*lists: list[str]) -> list[str]:
    combined: list[str] = []
    seen: set[str] = set()
    for predicted_ids in lists:
        for predicted_id in predicted_ids:
            if predicted_id and predicted_id not in seen:
                combined.append(predicted_id)
                seen.add(predicted_id)
    return combined


def compute_ranking_metrics(
    search_result_paths: list[Path | str],
    k: int,
    true_label_column: str = "true_qdrant_uuid",
    predicted_column_pattern: str = "predicted_",
    output_dir: Path | str | None = None,
) -> list[Path]:
    """Compute ranking metrics for each predicted column and a combined column."""
    saved_paths: list[Path] = []

    for search_result_path in search_result_paths:
        search_result_path = Path(search_result_path)
        predicted_columns = [
            column
            for column in _read_csv_fieldnames(search_result_path)
            if column.startswith(predicted_column_pattern)
        ]
        if not predicted_columns:
            raise ValueError(
                f"No columns matching {predicted_column_pattern!r} in {search_result_path}."
            )

        rows = _read_csv_rows(search_result_path)
        metrics_rows: list[dict[str, Any]] = []

        for predicted_column in predicted_columns:
            scores = _metric_scores_for_column(rows, true_label_column, predicted_column, k)
            metrics_rows.extend(
                [
                    {
                        "metric": "mrr",
                        "column": predicted_column,
                        "k": k,
                        "value": _mean(scores["mrr"]),
                    },
                    {
                        "metric": "map_at_k",
                        "column": predicted_column,
                        "k": k,
                        "value": _mean(scores["map_at_k"]),
                    },
                    {
                        "metric": "recall_at_k",
                        "column": predicted_column,
                        "k": k,
                        "value": _mean(scores["recall_at_k"]),
                    },
                ]
            )

        combined_scores = _combined_metric_scores(rows, true_label_column, predicted_columns, k)
        metrics_rows.extend(
            [
                {
                    "metric": "mrr",
                    "column": "combined",
                    "k": k,
                    "value": _mean(combined_scores["mrr"]),
                },
                {
                    "metric": "map_at_k",
                    "column": "combined",
                    "k": k,
                    "value": _mean(combined_scores["map_at_k"]),
                },
                {
                    "metric": "recall_at_k",
                    "column": "combined",
                    "k": k,
                    "value": _mean(combined_scores["recall_at_k"]),
                },
                {
                    "metric": "num_queries",
                    "column": "all",
                    "k": k,
                    "value": len(rows),
                },
            ]
        )

        output_path = (
            Path(output_dir)
            if output_dir is not None
            else search_result_path.parent
        )
        output_path.mkdir(parents=True, exist_ok=True)
        style_name = _style_name_from_search_result_path(search_result_path)
        metrics_path = output_path / f"ranking_metrics_{style_name}.csv"
        _write_metrics_csv(metrics_path, metrics_rows)
        saved_paths.append(metrics_path)

    return saved_paths


def run_search_evaluation_pipeline(
    related_descriptions_csv_path: Path | str,
    interim_dir: Path | str,
    database_name: str,
    qdrant_config: dict[str, Any] | None = None,
    openai_config: dict[str, Any] | None = None,
    db_config: dict[str, Any] | None = None,
    description_styles: tuple[str, ...] = ("short", "business", "technical"),
    search_query_columns: list[str] | None = None,
    n_results: int = 5,
    comment_style: str = "inline",
    comment_variant: str = "short",
    collection_names: tuple[str, ...] = ("ddl", "sql"),
    delete_collections: bool = True,
) -> list[Path]:
    """Populate Qdrant per description style, run search, and save ranked predictions."""
    related_descriptions_csv_path = Path(related_descriptions_csv_path)
    interim_dir = Path(interim_dir)
    scripts_dir = interim_dir / database_name / "scripts"
    search_dir = interim_dir / database_name / "search"
    search_dir.mkdir(parents=True, exist_ok=True)

    query_columns = search_query_columns or list(DEFAULT_SEARCH_QUERY_COLUMNS)
    rows = _read_csv_rows(related_descriptions_csv_path)
    filtered_rows = _filter_rows_with_scripts(rows, scripts_dir)
    if not filtered_rows:
        raise ValueError(f"No rows with SQL scripts found in {scripts_dir}.")

    saved_paths: list[Path] = []
    for style in description_styles:
        description_column = f"query_{style}"
        if description_column not in filtered_rows[0]:
            raise ValueError(
                f"Column {description_column!r} was not found in {related_descriptions_csv_path}."
            )

        corpus_pairs = _dedupe_corpus_pairs(filtered_rows, description_column, scripts_dir)
        client = initialize_vanna(
            qdrant_config=qdrant_config,
            openai_config=openai_config,
            db_config=db_config,
        )

        if delete_collections:
            for collection_name in collection_names:
                client.remove_collection(collection_name)

        table_ddls = render_table_ddls(
            database_name=database_name,
            comment_style=comment_style,
            comment_variant=comment_variant,
        )
        for ddl in tqdm(table_ddls, desc=f"Uploading DDL ({style})"):
            client.add_ddl(ddl)

        true_label_map: dict[str, str] = {}
        for row_uuid, description, sql in tqdm(corpus_pairs, desc=f"Uploading SQL ({style})"):
            qdrant_id = client.add_question_sql(question=description, sql=sql)
            true_label_map[row_uuid] = qdrant_id

        output_rows: list[dict[str, str]] = []
        search_total = len(filtered_rows) * len(query_columns)
        with tqdm(total=search_total, desc=f"Searching ({style})") as progress:
            for row in filtered_rows:
                output_row = dict(row)
                output_row["true_qdrant_uuid"] = true_label_map[row["uuid"]]

                for query_column in query_columns:
                    if query_column not in row:
                        raise ValueError(
                            f"Search column {query_column!r} was not found in "
                            f"{related_descriptions_csv_path}."
                        )
                    predicted_column = _predicted_column_name(query_column)
                    hits = client.get_similar_question_sql(
                        row[query_column],
                        n_results=n_results,
                    )
                    predicted_ids = _format_search_hit_ids(hits, client)
                    output_row[predicted_column] = ";".join(predicted_ids)
                    progress.update(1)

                output_rows.append(output_row)

        output_path = search_dir / f"{style}_top_{n_results}.csv"
        fieldnames = list(filtered_rows[0].keys()) + ["true_qdrant_uuid"]
        fieldnames.extend(
            _predicted_column_name(column)
            for column in query_columns
            if _predicted_column_name(column) not in fieldnames
        )
        _write_csv(output_path, fieldnames, output_rows)
        saved_paths.append(output_path)

    return saved_paths


def _metric_scores_for_column(
    rows: list[dict[str, str]],
    true_label_column: str,
    predicted_column: str,
    k: int,
) -> dict[str, list[float]]:
    mrr_scores: list[float] = []
    map_scores: list[float] = []
    recall_scores: list[float] = []

    for row in rows:
        relevant_id = row.get(true_label_column, "").strip()
        predicted_ids = _parse_predicted_ids(row.get(predicted_column, ""))
        if not relevant_id:
            continue
        mrr_scores.append(reciprocal_rank(relevant_id, predicted_ids))
        map_scores.append(average_precision_at_k(relevant_id, predicted_ids, k))
        recall_scores.append(recall_at_k(relevant_id, predicted_ids, k))

    return {"mrr": mrr_scores, "map_at_k": map_scores, "recall_at_k": recall_scores}


def _combined_metric_scores(
    rows: list[dict[str, str]],
    true_label_column: str,
    predicted_columns: list[str],
    k: int,
) -> dict[str, list[float]]:
    mrr_scores: list[float] = []
    map_scores: list[float] = []
    recall_scores: list[float] = []

    for row in rows:
        relevant_id = row.get(true_label_column, "").strip()
        if not relevant_id:
            continue
        per_column_predictions = [
            _parse_predicted_ids(row.get(predicted_column, ""))
            for predicted_column in predicted_columns
        ]
        combined_predictions = combine_predicted_ids(*per_column_predictions)
        mrr_scores.append(reciprocal_rank(relevant_id, combined_predictions))
        map_scores.append(average_precision_at_k(relevant_id, combined_predictions, k))
        recall_scores.append(recall_at_k(relevant_id, combined_predictions, k))

    return {"mrr": mrr_scores, "map_at_k": map_scores, "recall_at_k": recall_scores}


def _filter_rows_with_scripts(rows: list[dict[str, str]], scripts_dir: Path) -> list[dict[str, str]]:
    return [
        row
        for row in rows
        if (scripts_dir / f"{row['uuid']}.sql").exists()
    ]


def _dedupe_corpus_pairs(
    rows: list[dict[str, str]],
    description_column: str,
    scripts_dir: Path,
) -> list[tuple[str, str, str]]:
    seen: set[tuple[str, str, str]] = set()
    pairs: list[tuple[str, str, str]] = []

    for row in rows:
        row_uuid = row["uuid"]
        description = row[description_column].strip()
        sql = (scripts_dir / f"{row_uuid}.sql").read_text(encoding="utf-8").strip()
        key = (row_uuid, description, sql)
        if key in seen:
            continue
        seen.add(key)
        pairs.append(key)

    return pairs


def _format_search_hit_ids(hits: list[dict[str, Any]], client: VannaClient) -> list[str]:
    formatted_ids: list[str] = []
    for hit in hits:
        hit_id = str(hit.get("id", "")).strip()
        if not hit_id:
            continue
        if "-" in hit_id and hit_id.rsplit("-", 1)[-1] in client.id_suffixes.values():
            formatted_ids.append(hit_id)
        else:
            formatted_ids.append(
                client._format_point_id(hit_id, client.sql_collection_name)
            )
    return formatted_ids


def _predicted_column_name(search_query_column: str) -> str:
    match = re.match(r"query_(.+)_related$", search_query_column)
    if not match:
        raise ValueError(
            f"Search query column {search_query_column!r} must match 'query_<style>_related'."
        )
    return f"predicted_{match.group(1)}"


def _style_name_from_search_result_path(path: Path) -> str:
    match = re.match(r"(.+)_top_\d+$", path.stem)
    if not match:
        raise ValueError(f"Could not infer style name from search result file {path}.")
    return match.group(1)


def _parse_predicted_ids(value: str | None) -> list[str]:
    if not value or not str(value).strip():
        return []
    return [item.strip() for item in str(value).split(";") if item.strip()]


def _mean(values: list[float]) -> float:
    if not values:
        return 0.0
    return sum(values) / len(values)


def _read_csv_fieldnames(path: Path) -> list[str]:
    with path.open(newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        return list(reader.fieldnames or [])


def _read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as file:
        return list(csv.DictReader(file))


def _write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _write_metrics_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    fieldnames = ["metric", "column", "k", "value"]
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
