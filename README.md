# vanna-sql

<a target="_blank" href="https://cookiecutter-data-science.drivendata.org/">
    <img src="https://img.shields.io/badge/CCDS-Project%20template-328F97?logo=cookiecutter" />
</a>

Vanna AI based search and generation of SQL scripts

## Project Organization

```
├── LICENSE            <- Open-source license if one is chosen
├── Makefile           <- Makefile with convenience commands like `make data` or `make train`
├── README.md          <- The top-level README for developers using this project.
├── data
│   ├── external       <- Data from third party sources.
│   ├── interim        <- Intermediate data that has been transformed.
│   ├── processed      <- The final, canonical data sets for modeling.
│   └── raw            <- The original, immutable data dump.
│
├── docs               <- A default mkdocs project; see www.mkdocs.org for details
│
├── models             <- Trained and serialized models, model predictions, or model summaries
│
├── notebooks          <- Jupyter notebooks. Naming convention is a number (for ordering),
│                         the creator's initials, and a short `-` delimited description, e.g.
│                         `1.0-jqp-initial-data-exploration`.
│
├── pyproject.toml     <- Project configuration file with package metadata for 
│                         src and configuration for tools like black
│
├── references         <- Data dictionaries, manuals, and all other explanatory materials.
│
├── reports            <- Generated analysis as HTML, PDF, LaTeX, etc.
│   └── figures        <- Generated graphics and figures to be used in reporting
│
├── requirements.txt   <- The requirements file for reproducing the analysis environment, e.g.
│                         generated with `pip freeze > requirements.txt`
│
├── setup.cfg          <- Configuration file for flake8
│
└── src   <- Source code for dataset preparation, Vanna integration, and SQL generation.
    │
    ├── __init__.py             <- Makes src a Python module.
    │
    ├── config.py               <- Project paths and environment-based settings for Qdrant,
    │                              OpenAI-compatible APIs, embedding models, and devices.
    │
    ├── dataset.py              <- Dataset and SQLite helpers: render DDL templates with
    │                              Russian comments, split table DDLs, build/fill SQLite
    │                              databases, create schema descriptions with sample rows,
    │                              and rewrite query descriptions into several styles.
    │
    ├── prompts.py              <- Prompt builders for generating Russian query descriptions,
    │                              SQL scripts, and alternate description formats
    │                              (short, business, technical).
    │
    ├── script_generator.py     <- LLM-driven data generation utilities: create query
    │                              description CSV files, generate SQL scripts from those
    │                              descriptions, execute valid read-only SQL, and save
    │                              result datasets for evaluation.
    │
    └── vanna_connector.py      <- Custom Vanna client that combines Qdrant vector storage
    │                              with OpenAI-compatible chat, embeds SQL examples by
    │                              question/description text, connects to databases, and
    │                              guards intermediate SQL execution.
```

--------

