from __future__ import annotations

import csv
import json
import re
import sqlite3
from pathlib import Path
from typing import Any
from src.config import PROJECT_ROOT


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


def _normalize_comment_style(comment_style: str) -> str:
    try:
        return COMMENT_STYLE_ALIASES[comment_style.lower()]
    except KeyError as exc:
        supported = ", ".join(sorted(COMMENT_STYLE_ALIASES))
        raise ValueError(f"Unknown comment_style={comment_style!r}. Supported: {supported}.") from exc


def _comment_variant_path(comment_variant: str) -> Path:
    try:
        filename = COMMENT_VARIANTS[comment_variant.lower()]
    except KeyError as exc:
        supported = ", ".join(sorted(COMMENT_VARIANTS))
        raise ValueError(f"Unknown comment_variant={comment_variant!r}. Supported: {supported}.") from exc
    return BANK_EXTERNAL_DIR / filename


def _load_placeholders(comment_variant: str) -> dict[str, str]:
    variant_path = _comment_variant_path(comment_variant)
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


def _load_schema_mapping() -> dict[str, Any]:
    with BANK_SCHEMA_MAPPING_PATH.open(encoding="utf-8") as file:
        return json.load(file)


def render_bank_monitoring_ddl(
    comment_style: str,
    comment_variant: str,
) -> str:
    """Render bank monitoring DDL with the selected comment form and Russian descriptions."""
    normalized_style = _normalize_comment_style(comment_style)
    placeholders = _load_placeholders(comment_variant)
    template = BANK_SCHEMA_TEMPLATE_PATH.read_text(encoding="utf-8")
    style_section = _extract_comment_style_section(template, normalized_style)
    return _render_placeholders(style_section, placeholders)


def create_bank_monitoring_database(
    comment_style: str = "inline",
    comment_variant: str = "short",
    output_path: str | Path | None = None,
    overwrite: bool = True,
) -> Path:
    """Create an empty SQLite database from a rendered bank monitoring DDL template."""
    normalized_style = _normalize_comment_style(comment_style)
    normalized_variant = comment_variant.lower()
    ddl = render_bank_monitoring_ddl(normalized_style, normalized_variant)

    if output_path is None:
        filename = f"{BANK_DATASET_NAME}_{normalized_style}_{normalized_variant}.sqlite.db"
        db_path = BANK_PROCESSED_DIR / filename
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


def load_bank_monitoring_csv_data(
    db_path: str | Path,
    raw_dir: str | Path = BANK_RAW_DIR,
) -> dict[str, int]:
    """Load schema-aligned CSV files into a created bank monitoring SQLite database."""
    db_path = Path(db_path)
    raw_dir = Path(raw_dir)
    schema_mapping = _load_schema_mapping()
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


def build_bank_monitoring_database(
    comment_style: str = "inline",
    comment_variant: str = "short",
    output_path: str | Path | None = None,
    overwrite: bool = True,
) -> Path:
    """Create and fill the bank monitoring SQLite database in one pipeline step."""
    db_path = create_bank_monitoring_database(
        comment_style=comment_style,
        comment_variant=comment_variant,
        output_path=output_path,
        overwrite=overwrite,
    )
    load_bank_monitoring_csv_data(db_path)
    return db_path


if __name__ == "__main__":
    build_bank_monitoring_database()