from __future__ import annotations

import csv
from pathlib import Path
import re
import sqlite3
from typing import Any
from uuid import uuid4

import pandas as pd

from src.config import INTERIM_DATA_DIR
from src.dataset import BANK_DATASET_NAME, build_schema_description_with_samples
from src.prompts import build_query_description_prompt, build_sql_generation_prompt

DEFAULT_COUNTS_BY_DIFFICULTY = {
    "easy": 20,
    "medium": 20,
    "hard": 20,
}


def generate_query_descriptions(
    client: Any,
    model: str,
    comment_style: str = "inline",
    comment_variant: str = "short",
    database_name: str = BANK_DATASET_NAME,
    counts_by_difficulty: dict[str, int] | None = None,
    temperature: float = 1.0,
) -> tuple[Path, Path, Path]:
    schema_description, sqlite_db_path = build_schema_description_with_samples(
        comment_style=comment_style,
        comment_variant=comment_variant,
        database_name=database_name,
    )

    interim_dir = INTERIM_DATA_DIR / database_name
    interim_dir.mkdir(parents=True, exist_ok=True)

    schema_description_path = (
        interim_dir / f"schema_description_{comment_style}_{comment_variant}.txt"
    )
    schema_description_path.write_text(schema_description, encoding="utf-8")

    descriptions_csv_path = (
        interim_dir / f"query_descriptions_{comment_style}_{comment_variant}.csv"
    )
    counts = counts_by_difficulty or DEFAULT_COUNTS_BY_DIFFICULTY

    with descriptions_csv_path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(
            file,
            fieldnames=["database_name", "query", "difficulty", "uuid"],
        )
        writer.writeheader()

        for difficulty, count in counts.items():
            for _ in range(count):
                messages = build_query_description_prompt(
                    schema_description=schema_description,
                    difficulty=difficulty,
                    database_name=database_name,
                )
                query = _call_openai_chat(
                    client=client,
                    model=model,
                    messages=messages,
                    temperature=temperature,
                ).strip()
                writer.writerow(
                    {
                        "database_name": database_name,
                        "query": query,
                        "difficulty": difficulty,
                        "uuid": str(uuid4()),
                    }
                )

    return descriptions_csv_path, schema_description_path, sqlite_db_path


def generate_sql_scripts_and_results(
    client: Any,
    model: str,
    sqlite_db_path: str | Path,
    interim_dir: str | Path,
    descriptions_csv_path: str | Path | None = None,
    schema_description_path: str | Path | None = None,
    temperature: float = 0.2,
) -> dict[str, int]:
    sqlite_db_path = Path(sqlite_db_path)
    interim_dir = Path(interim_dir)
    descriptions_csv_path = (
        Path(descriptions_csv_path)
        if descriptions_csv_path is not None
        else _latest_matching_file(interim_dir, "query_descriptions_*.csv")
    )
    schema_description_path = (
        Path(schema_description_path)
        if schema_description_path is not None
        else _latest_matching_file(interim_dir, "schema_description_*.txt")
    )

    schema_description = schema_description_path.read_text(encoding="utf-8")
    scripts_dir = interim_dir / "scripts"
    results_dir = interim_dir / "results"
    scripts_dir.mkdir(parents=True, exist_ok=True)
    results_dir.mkdir(parents=True, exist_ok=True)

    counters = {
        "total": 0,
        "generated": 0,
        "saved": 0,
        "failed": 0,
        "empty": 0,
        "invalid_sql": 0,
    }

    with descriptions_csv_path.open(newline="", encoding="utf-8") as file:
        rows = list(csv.DictReader(file))

    with sqlite3.connect(sqlite_db_path) as connection:
        for row in rows:
            counters["total"] += 1
            messages = build_sql_generation_prompt(
                schema_description=schema_description,
                query=row["query"],
                difficulty=row["difficulty"],
            )
            llm_response = _call_openai_chat(
                client=client,
                model=model,
                messages=messages,
                temperature=temperature,
            )
            counters["generated"] += 1
            sql = extract_sql(llm_response).strip()

            if not _is_read_only_sql(sql):
                counters["invalid_sql"] += 1
                continue

            try:
                result = pd.read_sql_query(sql, connection)
            except Exception:
                counters["failed"] += 1
                continue

            if result.empty:
                counters["empty"] += 1
                continue

            result = _normalize_result(result)
            query_uuid = row["uuid"]
            (scripts_dir / f"{query_uuid}.txt").write_text(sql, encoding="utf-8")
            result.to_csv(results_dir / f"{query_uuid}.csv", index=False)
            counters["saved"] += 1

    return counters


def extract_sql(llm_response: str) -> str:
    sqls = re.findall(
        r"\bCREATE\s+TABLE\b.*?\bAS\b.*?;", llm_response, re.DOTALL | re.IGNORECASE
    )
    if sqls:
        return sqls[-1]

    sqls = re.findall(r"\bWITH\b .*?;", llm_response, re.DOTALL | re.IGNORECASE)
    if sqls:
        return sqls[-1]

    sqls = re.findall(r"\bSELECT\b .*?;", llm_response, re.DOTALL | re.IGNORECASE)
    if sqls:
        return sqls[-1]

    sqls = re.findall(r"```sql\s*\n(.*?)```", llm_response, re.DOTALL | re.IGNORECASE)
    if sqls:
        return sqls[-1].strip()

    sqls = re.findall(r"```(.*?)```", llm_response, re.DOTALL | re.IGNORECASE)
    if sqls:
        return sqls[-1].strip()

    return llm_response


def _call_openai_chat(
    client: Any,
    model: str,
    messages: list[dict[str, str]],
    temperature: float,
) -> str:
    response = client.chat.completions.create(
        model=model,
        messages=messages,
        temperature=temperature,
    )
    return _extract_response_text(response)


def _extract_response_text(response: Any) -> str:
    choice = response.choices[0]
    if isinstance(choice, dict):
        message = choice.get("message", {})
        return str(message.get("content", choice.get("text", "")))

    if hasattr(choice, "message") and hasattr(choice.message, "content"):
        return str(choice.message.content)

    if hasattr(choice, "text"):
        return str(choice.text)

    raise ValueError("Could not extract text from OpenAI-compatible response.")


def _latest_matching_file(directory: Path, pattern: str) -> Path:
    matches = sorted(directory.glob(pattern), key=lambda path: path.stat().st_mtime, reverse=True)
    if not matches:
        raise FileNotFoundError(f"No files matching {pattern!r} were found in {directory}.")
    return matches[0]


def _is_read_only_sql(sql: str) -> bool:
    sql_without_comments = re.sub(r"(?m)^\s*--.*$", "", sql).strip()
    return bool(re.match(r"^(SELECT|WITH)\b", sql_without_comments, flags=re.IGNORECASE))


def _normalize_result(result: pd.DataFrame) -> pd.DataFrame:
    sorted_columns = sorted(result.columns)
    normalized = result[sorted_columns].copy()
    return normalized.sort_values(
        by=sorted_columns,
        key=lambda column: column.astype(str),
    ).reset_index(drop=True)
