# Generation Quality Evaluation

This document describes how we measure the quality of SQL **generation** in our Vanna-based assistant. The implementation lives in [`src/generation_metrics.py`](../src/generation_metrics.py) and is exercised from [`notebooks/experiments/2_generate_scripts_and_queries.ipynb`](../notebooks/experiments/2_generate_scripts_and_queries.ipynb).

## Goal

We evaluate whether Vanna can **generate executable SQL** that returns the **same result** as a known ground-truth query. Unlike search evaluation, this tests the full generation path: retrieval context (DDL + similar examples) plus LLM synthesis via `generate_sql`.

Quality is measured by **executing** both ground-truth and generated SQL against SQLite and comparing the resulting tables.

## What we are testing

Generation quality is evaluated across combinations of:

- **LLM model** (required `models` dict: folder key → model name passed to `openai_config["model"]`)
- **DDL comment style**: `inline`, `yaml`
- **Query description style**: `short`, `business`, `technical`

Each combination uses matching artifacts end-to-end:

- LLM model overridden per `models` entry while other `openai_config` fields stay the same
- DDL comments rendered with `render_table_ddls(comment_style, comment_variant=description_style)`
- SQLite database: `data/processed/{database}/{database}_{comment_style}_{description_style}.sqlite.db`
- Query text from `query_{description_style}` (or a custom `source_column`)

Subfolder name: `{comment_style}_{description_style}_{model_key}` (e.g. `yaml_short_gpt4`).

Total combos per run: `len(models) × len(comment_styles) × len(description_styles)`.

## Input data

| Artifact | Typical path | Role |
|----------|--------------|------|
| Descriptions CSV | `data/interim/{database}/query_descriptions_*_rewritten.csv` | Query text and difficulty per uuid |
| Ground-truth SQL | `data/interim/{database}/scripts/{uuid}.txt` | Reference SQL (used for training folds) |
| Ground-truth results | `data/interim/{database}/results/{uuid}.csv` | Reference query output |

The pipeline:

1. Keeps only rows with an existing `scripts/{uuid}.txt`.
2. Dedupes unique `(uuid, description, sql)` corpus pairs.
3. Builds one eval row per uuid: `uuid`, `query` (description text), `difficulty`.

## Evaluation pipeline

`run_generation_evaluation_pipeline` runs **stratified k-fold cross-validation** (default `n_folds=5`, stratified by `difficulty`) independently for each model × style combination.

```text
For each model_key in models:
  For each combo (inline/yaml × short/business/technical):
    StratifiedKFold on eval rows
      For each fold:
        1. Delete Qdrant collections (ddl, sql)
        2. Initialize Vanna with combo-specific SQLite DB and LLM model
        3. Ingest DDLs for this comment style + variant
        4. Train: add_question_sql for train-fold uuids only
        5. Test: generate_sql(query) for test-fold uuids
        6. Save generated SQL and executed results
```

### Cross-validation design

- **Train fold**: question–SQL pairs from the train uuids are added to Qdrant via `add_question_sql`. Test uuids are excluded to prevent leakage.
- **Test fold**: each test query is passed to `generate_sql`. Across all folds, every uuid is predicted exactly once per combo.
- **Stratification**: folds preserve the proportion of `easy`, `medium`, and `hard` queries.

### Per test query

1. `generate_sql(query)` produces SQL text.
2. SQL is saved to `generation/prediction_scripts/{combo}/{uuid}.txt` regardless of validity.
3. If SQL passes read-only validation (`SELECT` / `WITH` only), it is executed via `client.run_sql`.
4. On success with a non-empty result, the dataframe is normalized and saved to `generation/prediction_results/{combo}/{uuid}.csv`.

### Result normalization

Before saving or comparing, results are normalized the same way as in [`src/script_generator.py`](../src/script_generator.py):

1. Sort columns alphabetically.
2. Sort rows by all columns (values cast to string).
3. Reset index.

This makes row order and column order irrelevant during comparison.

### Output directories

```
data/interim/{database}/generation/
  prediction_scripts/{combo}/{uuid}.txt
  prediction_results/{combo}/{uuid}.csv
  metrics/{combo}.csv
```

The pipeline returns the list of `prediction_results/{combo}` paths.

## Metrics

`compute_generation_metrics` compares predicted result CSVs against ground-truth results and assigns a **label** per uuid.

### Evaluated uuids

Only uuids that have a ground-truth file at `results/{uuid}.csv` are included. Difficulty is taken from the descriptions CSV.

### Label definitions

Labels are assigned in priority order:

| Label | Condition |
|-------|-----------|
| **Not generated** | No `{uuid}.csv` in the predicted results folder (SQL missing, invalid, execution failed, or empty result) |
| **Not matching number of rows and cols** | Both row count and column count differ from ground truth |
| **Not matching number of rows** | Only row count differs |
| **Not matching number of columns** | Only column count differs |
| **Not matching values** | Same shape, but cell values differ after string conversion |
| **Everything matches** | Same shape and all values equal as strings |

Value comparison uses `dataframe.astype(str).equals(...)` on normalized dataframes.

### Output

Per combo:

```
data/interim/{database}/generation/metrics/{combo}.csv
```

Columns: `uuid`, `difficulty`, `label`.

Typical analysis:

- Overall match rate: share of `Everything matches`.
- Breakdown by `difficulty` to see whether hard queries fail more often.
- Comparison across combos to see which model, DDL comment style, and description style produce the best generation.

## Parameters

| Parameter | Default | Effect |
|-----------|---------|--------|
| `models` | (required) | Dict mapping subfolder key to LLM model name (overrides `openai_config["model"]`) |
| `comment_styles` | `inline`, `yaml` | DDL comment format |
| `description_styles` | `short`, `business`, `technical` | Query text column and SQLite DB variant |
| `source_column` | `None` → `query_{description_style}` | Override query text column |
| `n_folds` | `5` | Cross-validation folds |
| `delete_collections` | `True` | Reset Qdrant before each fold |
| `descriptions_csv_path` | (required) | Typically `*_rewritten.csv` |

## Comparison with search evaluation

| Aspect | Search evaluation | Generation evaluation |
|--------|-------------------|----------------------|
| Vanna method | `get_similar_question_sql` | `generate_sql` |
| Corpus in Qdrant | Full dataset | Train fold only |
| Ground truth | Qdrant point id | Executed result CSV |
| Metrics | MRR, MAP@k, Recall@k | Result-match labels |
| Style dimensions | Description style (+ related queries) | Model × DDL style × description style |
| Validation | Ranking | k-fold CV stratified by difficulty |

## Limitations

- Quality is judged by **result equivalence**, not SQL text equality. Different SQL that returns the same table is labeled `Everything matches`.
- Conversely, syntactically similar SQL with different results is labeled `Not matching values`.
- Failed or non-read-only SQL is lumped into `Not generated`; there is no separate label for execution errors vs. invalid SQL.
- Each combo × fold run reinitializes Qdrant and reloads DDLs, so evaluation is computationally expensive (`len(models) × len(comment_styles) × len(description_styles)` combos × `n_folds` × LLM calls per test query).
- Only uuids with pre-generated ground-truth scripts and results are evaluated.
