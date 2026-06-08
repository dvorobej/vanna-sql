# Search Quality Evaluation

This document describes how we measure the quality of semantic search in our Vanna-based SQL assistant. The implementation lives in [`src/search_metrics.py`](../src/search_metrics.py) and is exercised from [`notebooks/experiments/2_generate_scripts_and_queries.ipynb`](../notebooks/experiments/2_generate_scripts_and_queries.ipynb).

## Goal

We evaluate whether the vector store can retrieve the **correct SQL example** when given a natural-language query description. Search quality is measured as a **ranking problem**: for each query, we know the ground-truth example and check whether it appears in the top-*k* retrieved results.

## What we are testing

Search quality depends on:

- the **description style** used to index corpus examples (`short`, `business`, or `technical`);
- the **query phrasing** used at search time (related-query variants from the expanded dataset).

Generation is **not** involved in this evaluation. We only call `get_similar_question_sql`, not `generate_sql`.

## Input data

| Artifact | Typical path | Role |
|----------|--------------|------|
| Related descriptions CSV | `data/interim/{database}/query_descriptions/query_descriptions_*_rewritten_related.csv` | Query variants and metadata |
| Ground-truth SQL scripts | `data/interim/{database}/scripts/{uuid}.sql` | SQL paired with each uuid |

The pipeline keeps only rows whose uuid has a corresponding file in `scripts/`. Corpus pairs are deduplicated by `(uuid, description, sql)` so each unique example is indexed once.

### Description columns

- **Indexing column** (per evaluation run): `query_{style}` where `style` is `short`, `business`, or `technical`.
- **Search query columns** (default): `query_short_related`, `query_business_related`, `query_technical_related`.

Related columns represent paraphrased or expanded variants of the original query. This lets us test whether search still finds the right SQL when the user wording differs from the indexed description.

## Evaluation pipeline

`run_search_evaluation_pipeline` performs the following steps **once per description style** (`short`, `business`, `technical`):

1. **Filter and prepare corpus** — load the related descriptions CSV; keep rows with existing SQL scripts; dedupe unique `(uuid, description, sql)` tuples.
2. **Reset Qdrant** (optional, default `delete_collections=True`) — delete `ddl` and `sql` collections.
3. **Initialize Vanna** — connect to Qdrant, embedding model, and SQLite.
4. **Ingest DDLs** — `render_table_ddls(database_name, comment_style, comment_variant)` → `add_ddl` for each table.
5. **Ingest SQL examples** — for each corpus pair, `add_question_sql(question=description, sql=sql)` and record the returned Qdrant point id as the ground-truth label (`true_qdrant_uuid`).
6. **Run search** — for every row in the filtered dataset and every search query column, call `get_similar_question_sql(query_text, n_results=k)`.
7. **Save predictions** — write `data/interim/{database}/search/{style}_top_{k}.csv` with semicolon-separated predicted ids per column (`predicted_short`, `predicted_business`, `predicted_technical`).

### Embedding behavior

At search time, `get_similar_question_sql` embeds **only the query text**. This matches the user-facing scenario: the user asks a question in natural language, and retrieval should be driven by semantic similarity of descriptions, not by SQL syntax overlap.

## Metrics

`compute_ranking_metrics` reads the search result CSVs and computes aggregate ranking metrics per predicted column and for a **combined** ranking.

For each query row:

- **Ground truth**: `true_qdrant_uuid` — the Qdrant id of the correctly matching example for that uuid and description style.
- **Predictions**: ordered list of retrieved ids from a `predicted_*` column.

### Metric definitions

| Metric | Meaning |
|--------|---------|
| **MRR** (Mean Reciprocal Rank) | Average of `1 / rank` where the ground-truth id first appears; `0` if not found |
| **MAP@k** (Mean Average Precision at k) | Average of `1 / rank` if the ground-truth id is within top-*k*; `0` otherwise |
| **Recall@k** | Fraction of queries where the ground-truth id appears anywhere in top-*k* |

For the **combined** column, predicted id lists from all `predicted_*` columns are merged with `combine_predicted_ids` (deduplicated, preserving first-seen order). Metrics are then computed on this merged ranking.

### Output

Per style, metrics are saved to:

```
data/interim/{database}/search/ranking_metrics_{style}.csv
```

Columns: `metric`, `column`, `k`, `value`.

Reported rows include per-column scores (`predicted_short`, `predicted_business`, `predicted_technical`), combined scores, and `num_queries`.

## Parameters worth varying

| Parameter | Default | Effect |
|-----------|---------|--------|
| `description_styles` | `short`, `business`, `technical` | Which `query_{style}` column indexes the corpus |
| `comment_style` | `inline` | DDL comment format in Qdrant |
| `comment_variant` | `short` | DDL comment verbosity variant |
| `n_results` | `5` | Retrieval depth (*k* for metrics) |
| `search_query_columns` | related columns | Which query phrasings are evaluated |
| `delete_collections` | `True` | Whether to wipe Qdrant before each style run |

## Interpretation

- High **Recall@k** means the correct example is usually among the top results.
- **MRR** and **MAP@k** penalize correct answers that appear lower in the ranking.
- Comparing metrics across `short` / `business` / `technical` shows which description style is easiest to retrieve.
- Comparing `predicted_*` columns shows robustness to paraphrased (related) query wording.
- The combined column estimates performance when multiple query variants are searched and merged.

## Limitations

- Metrics assume a **single relevant document** per query (the uuid's canonical example for that style).
