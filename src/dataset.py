from __future__ import annotations

import csv
import io
import json
from pathlib import Path
import re
import sqlite3
from typing import Any

from tqdm import tqdm

from src.config import PROJECT_ROOT
from src.llm_client import call_openai_chat_with_retries
from src.prompts import build_query_description_rewrite_prompt

BANK_DATASET_NAME = "bank_transaction_monitoring"
BANK_RAW_DIR = PROJECT_ROOT / "data" / "raw" / BANK_DATASET_NAME
BANK_EXTERNAL_DIR = PROJECT_ROOT / "data" / "external" / BANK_DATASET_NAME
BANK_PROCESSED_DIR = PROJECT_ROOT / "data" / "processed" / BANK_DATASET_NAME
BANK_SCHEMA_TEMPLATE_PATH = BANK_RAW_DIR / "schema_template.sql"
BANK_SCHEMA_MAPPING_PATH = BANK_RAW_DIR / "schema_mapping.json"

COMMENT_STYLE_ALIASES = {
    "inline": "inline",
    "option1": "inline",
    "option_1": "inline",
    "yaml": "yaml",
    "option3": "yaml",
    "option_3": "yaml",
}
COMMENT_VARIANTS = {
    "short": "comments_short.json",
    "business": "comments_business.json",
    "technical": "comments_technical.json",
}
PLACEHOLDER_PATTERN = re.compile(r"\{\{([A-Za-z0-9_.]+)\}\}")


def get_database_raw_dir(database_name: str = BANK_DATASET_NAME) -> Path:
    return PROJECT_ROOT / "data" / "raw" / database_name


def get_database_external_dir(database_name: str = BANK_DATASET_NAME) -> Path:
    return PROJECT_ROOT / "data" / "external" / database_name


def get_database_processed_dir(database_name: str = BANK_DATASET_NAME) -> Path:
    return PROJECT_ROOT / "data" / "processed" / database_name


def get_schema_template_path(database_name: str = BANK_DATASET_NAME) -> Path:
    return get_database_raw_dir(database_name) / "schema_template.sql"


def get_schema_mapping_path(database_name: str = BANK_DATASET_NAME) -> Path:
    return get_database_raw_dir(database_name) / "schema_mapping.json"


def get_sqlite_database_path(
    database_name: str = BANK_DATASET_NAME,
    comment_style: str = "inline",
    comment_variant: str = "short",
) -> Path:
    normalized_style = _normalize_comment_style(comment_style)
    normalized_variant = comment_variant.lower()
    filename = f"{database_name}_{normalized_style}_{normalized_variant}.sqlite.db"
    return get_database_processed_dir(database_name) / filename


def _normalize_comment_style(comment_style: str) -> str:
    try:
        return COMMENT_STYLE_ALIASES[comment_style.lower()]
    except KeyError as exc:
        supported = ", ".join(sorted(COMMENT_STYLE_ALIASES))
        raise ValueError(f"Unknown comment_style={comment_style!r}. Supported: {supported}.") from exc


def _comment_variant_path(
    comment_variant: str,
    database_name: str = BANK_DATASET_NAME,
) -> Path:
    try:
        filename = COMMENT_VARIANTS[comment_variant.lower()]
    except KeyError as exc:
        supported = ", ".join(sorted(COMMENT_VARIANTS))
        raise ValueError(f"Unknown comment_variant={comment_variant!r}. Supported: {supported}.") from exc
    return get_database_external_dir(database_name) / filename


def _load_placeholders(
    comment_variant: str,
    database_name: str = BANK_DATASET_NAME,
) -> dict[str, str]:
    variant_path = _comment_variant_path(comment_variant, database_name)
    with variant_path.open(encoding="utf-8") as file:
        payload = json.load(file)

    placeholders = payload.get("placeholders")
    if not isinstance(placeholders, dict):
        raise ValueError(f"{variant_path} must contain a 'placeholders' object.")

    return {str(key): str(value) for key, value in placeholders.items()}


def _extract_comment_style_section(template: str, comment_style: str) -> str:
    section_pattern = re.compile(
        rf"-- BEGIN COMMENT_STYLE:{re.escape(comment_style)}\n"
        rf"(?P<section>.*?)"
        rf"-- END COMMENT_STYLE:{re.escape(comment_style)}",
        flags=re.DOTALL,
    )
    match = section_pattern.search(template)
    if not match:
        raise ValueError(f"Template section for comment_style={comment_style!r} was not found.")
    return match.group("section").strip() + "\n"


def _render_placeholders(template: str, placeholders: dict[str, str]) -> str:
    missing: set[str] = set()

    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        if key not in placeholders:
            missing.add(key)
            return match.group(0)
        return placeholders[key]

    rendered = PLACEHOLDER_PATTERN.sub(replace, template)
    if missing:
        missing_values = ", ".join(sorted(missing))
        raise ValueError(f"Missing placeholder values: {missing_values}.")
    return rendered


def _load_schema_mapping(database_name: str = BANK_DATASET_NAME) -> dict[str, Any]:
    with get_schema_mapping_path(database_name).open(encoding="utf-8") as file:
        return json.load(file)


def render_ddl(
    comment_style: str,
    comment_variant: str,
    database_name: str = BANK_DATASET_NAME,
) -> str:
    """Render bank monitoring DDL with the selected comment form and Russian descriptions."""
    normalized_style = _normalize_comment_style(comment_style)
    placeholders = _load_placeholders(comment_variant, database_name)
    template = get_schema_template_path(database_name).read_text(encoding="utf-8")
    style_section = _extract_comment_style_section(template, normalized_style)
    return _render_placeholders(style_section, placeholders)


def render_table_ddls(
    database_name: str = BANK_DATASET_NAME,
    comment_style: str = "inline",
    comment_variant: str = "short",
) -> list[str]:
    """Render one filled DDL script per table for Vanna training."""
    ddl = render_ddl(
        comment_style=comment_style,
        comment_variant=comment_variant,
        database_name=database_name,
    )
    table_pattern = re.compile(
        r"(?ms)(?:(?<=\A)|(?<=\n\n))"
        r"(?P<script>(?:(?:--[^\n]*\n)+)?CREATE\s+TABLE\b.*?;\s*)",
    )
    scripts = [match.group("script").strip() for match in table_pattern.finditer(ddl)]
    if not scripts:
        raise ValueError("No CREATE TABLE statements were found in the rendered DDL.")
    return scripts


def _extract_table_name_from_ddl(ddl: str) -> str | None:
    match = re.search(r"\bCREATE\s+TABLE\s+([A-Za-z_][A-Za-z0-9_]*)", ddl, flags=re.IGNORECASE)
    if not match:
        return None
    return match.group(1)


def _format_sample_rows(columns: list[str], rows: list[tuple[Any, ...]]) -> str:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(columns)
    writer.writerows(rows)
    return buffer.getvalue().strip()


def build_schema_description_with_samples(
    comment_style: str = "inline",
    comment_variant: str = "short",
    database_name: str = BANK_DATASET_NAME,
    sample_rows: int = 5,
) -> tuple[str, Path]:
    """Combine rendered table DDLs with sample rows from the matching SQLite database."""
    normalized_style = _normalize_comment_style(comment_style)
    normalized_variant = comment_variant.lower()
    db_path = get_sqlite_database_path(
        database_name=database_name,
        comment_style=normalized_style,
        comment_variant=normalized_variant,
    )
    if not db_path.exists():
        db_path = build_database(
            comment_style=normalized_style,
            comment_variant=normalized_variant,
            database_name=database_name,
        )

    schema_mapping = _load_schema_mapping(database_name)
    table_ddls = render_table_ddls(
        database_name=database_name,
        comment_style=normalized_style,
        comment_variant=normalized_variant,
    )
    ddls_by_table = {
        table_name: ddl
        for ddl in table_ddls
        if (table_name := _extract_table_name_from_ddl(ddl)) is not None
    }

    blocks: list[str] = []
    matched_tables: set[str] = set()

    with sqlite3.connect(db_path) as connection:
        for table_name in schema_mapping:
            ddl = ddls_by_table.get(table_name)
            if ddl is None:
                continue

            matched_tables.add(table_name)
            cursor = connection.execute(f"SELECT * FROM {table_name} LIMIT ?", (sample_rows,))
            rows = cursor.fetchall()
            columns = [description[0] for description in cursor.description]
            sample_text = _format_sample_rows(columns, rows)

            blocks.append(
                "\n".join(
                    [
                        f"DDL script for table {table_name}",
                        ddl,
                        "",
                        f"Output of the first {sample_rows} rows of table {table_name}",
                        sample_text,
                    ]
                )
            )

    unmatched_ddls = [
        ddl
        for ddl in table_ddls
        if (table_name := _extract_table_name_from_ddl(ddl)) is None or table_name not in matched_tables
    ]
    if unmatched_ddls:
        blocks.append("Other DDL scripts without matching tables\n" + "\n\n".join(unmatched_ddls))

    return "\n\n".join(blocks), db_path


def rewrite_query_descriptions_csv(
    descriptions_csv_path: str | Path,
    client: Any,
    model: str,
    schema_description_path: str | Path | None = None,
    rewrite_styles: tuple[str, ...] = ("short", "business", "technical"),
    source_column: str = "query",
    temperature: float = 0.9,
    output_path: str | Path | None = None,
) -> Path:
    """Rewrite query descriptions into multiple formats and save an augmented CSV."""
    descriptions_csv_path = Path(descriptions_csv_path)
    schema_description_path = (
        Path(schema_description_path)
        if schema_description_path is not None
        else _latest_schema_description_path(descriptions_csv_path.parent)
    )
    output_path = (
        Path(output_path)
        if output_path is not None
        else descriptions_csv_path.with_name(f"{descriptions_csv_path.stem}_rewritten.csv")
    )

    schema_description = schema_description_path.read_text(encoding="utf-8")
    with descriptions_csv_path.open(newline="", encoding="utf-8") as file:
        rows = list(csv.DictReader(file))
        fieldnames = list(file.seek(0) or csv.DictReader(file).fieldnames or [])

    if not rows:
        raise ValueError(f"No rows found in {descriptions_csv_path}.")
    if source_column not in rows[0]:
        raise ValueError(f"Column {source_column!r} was not found in {descriptions_csv_path}.")

    rewrite_columns = [f"{source_column}_{style}" for style in rewrite_styles]
    output_fieldnames = [*fieldnames, *[column for column in rewrite_columns if column not in fieldnames]]

    total = len(rows) * len(rewrite_styles)
    with tqdm(total=total, desc="Rewriting query descriptions") as progress:
        for row in rows:
            difficulty = row.get("difficulty")
            for style, column in zip(rewrite_styles, rewrite_columns, strict=True):
                messages = build_query_description_rewrite_prompt(
                    schema_description=schema_description,
                    query_description=row[source_column],
                    rewrite_style=style,
                    difficulty=difficulty,
                )
                row[column] = call_openai_chat_with_retries(
                    client=client,
                    model=model,
                    messages=messages,
                    temperature=temperature,
                )
                progress.update(1)

    with output_path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=output_fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    return output_path


def _latest_schema_description_path(directory: Path) -> Path:
    matches = sorted(
        directory.glob("schema_description_*.txt"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not matches:
        raise FileNotFoundError(f"No schema_description_*.txt files were found in {directory}.")
    return matches[0]


def create_database(
    comment_style: str = "inline",
    comment_variant: str = "short",
    output_path: str | Path | None = None,
    overwrite: bool = True,
    database_name: str = BANK_DATASET_NAME,
) -> Path:
    """Create an empty SQLite database from a rendered bank monitoring DDL template."""
    normalized_style = _normalize_comment_style(comment_style)
    normalized_variant = comment_variant.lower()
    ddl = render_ddl(
        comment_style=normalized_style,
        comment_variant=normalized_variant,
        database_name=database_name,
    )

    if output_path is None:
        db_path = get_sqlite_database_path(
            database_name=database_name,
            comment_style=normalized_style,
            comment_variant=normalized_variant,
        )
    else:
        db_path = Path(output_path)

    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        if not overwrite:
            raise FileExistsError(f"Database already exists: {db_path}")
        db_path.unlink()

    with sqlite3.connect(db_path) as connection:
        connection.executescript(ddl)
        connection.commit()

    return db_path


def load_csv_data(
    db_path: str | Path,
    database_name: str = BANK_DATASET_NAME,
    raw_dir: str | Path | None = None,
) -> dict[str, int]:
    """Load schema-aligned CSV files into a created bank monitoring SQLite database."""
    db_path = Path(db_path)
    raw_dir = get_database_raw_dir(database_name) if raw_dir is None else Path(raw_dir)
    schema_mapping = _load_schema_mapping(database_name)
    inserted_counts: dict[str, int] = {}

    with sqlite3.connect(db_path) as connection:
        for table_name, table_meta in schema_mapping.items():
            csv_path = raw_dir / f"{table_name}.csv"
            columns = list(table_meta["columns"])
            placeholders = ", ".join("?" for _ in columns)
            column_list = ", ".join(columns)
            statement = f"INSERT INTO {table_name} ({column_list}) VALUES ({placeholders})"

            with csv_path.open(newline="", encoding="utf-8") as file:
                rows = list(csv.DictReader(file))

            values = [
                tuple(row[column] if row[column] != "" else None for column in columns)
                for row in rows
            ]
            connection.executemany(statement, values)
            inserted_counts[table_name] = len(values)

        connection.commit()

    return inserted_counts


def build_database(
    comment_style: str = "inline",
    comment_variant: str = "short",
    output_path: str | Path | None = None,
    overwrite: bool = True,
    database_name: str = BANK_DATASET_NAME,
) -> Path:
    """Create and fill the bank monitoring SQLite database in one pipeline step."""
    db_path = create_database(
        comment_style=comment_style,
        comment_variant=comment_variant,
        output_path=output_path,
        overwrite=overwrite,
        database_name=database_name,
    )
    load_csv_data(db_path, database_name=database_name)
    return db_path


if __name__ == "__main__":
    build_database()