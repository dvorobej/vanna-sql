from __future__ import annotations
from typing import List
from copy import deepcopy
from pathlib import Path
from typing import Any
from src.config import OPENAI_API_KEY, OPENAI_API_URL, OPENAI_MODEL, DENSE_EMBEDDING_MODEL_PATH, DEVICE
from openai import OpenAI
from qdrant_client import models
from vanna.legacy.qdrant.qdrant import Qdrant_VectorStore
from vanna.legacy.openai.openai_chat import OpenAI_Chat
from vanna.legacy.utils import deterministic_uuid
from sentence_transformers import SentenceTransformer
import httpx


class QdrantVectorStore(Qdrant_VectorStore):
    """Qdrant vector store that embeds SQL examples by question text only."""
    def __init__(self, config: dict | None = None, **kwargs):
        config = config or {}
        self.embedding_model = SentenceTransformer(config.get("fastembed_model", DENSE_EMBEDDING_MODEL_PATH),
                                                   device=config.get("device", DEVICE))

        super().__init__(config=config, **kwargs)


    def generate_embedding(self, data: str, **kwargs) -> List[float]:
        return self.embedding_model.encode(data, show_progress_bar=False).tolist()


    def add_question_sql(self, question: str, sql: str, **kwargs) -> str:
        question_answer = "Question: {0}\n\nSQL: {1}".format(question, sql)
        id = deterministic_uuid(question_answer)

        self._client.upsert(
            self.sql_collection_name,
            points=[
                models.PointStruct(
                    id=id,
                    vector=self.generate_embedding(question),
                    payload={
                        "question": question,
                        "sql": sql,
                    },
                )
            ],
        )

        return self._format_point_id(id, self.sql_collection_name)


    def get_similar_question_sql(self, question: str, n_results: int | None = None, **kwargs) -> list:
        n_results = n_results or self.n_results
        results = self._client.query_points(
            self.sql_collection_name,
            query=self.generate_embedding(question),
            limit=n_results,
            with_payload=True,
        ).points

        return [dict(result.payload) for result in results]


    def is_sql_read_only_code(self, sql: str) -> bool:
        """Return True only for read-only SELECT-style SQL accepted by Vanna."""
        if not sql or not sql.strip():
            return False
        return self.is_sql_valid(sql.strip())


    def generate_sql(self, question: str, allow_llm_to_see_data=False, **kwargs) -> str:
        """
        Example:
        ```python
        vn.generate_sql("What are the top 10 customers by sales?")
        ```

        Uses the LLM to generate a SQL query that answers a question. It runs the following methods:

        - [`get_similar_question_sql`][vanna.base.base.VannaBase.get_similar_question_sql]

        - [`get_related_ddl`][vanna.base.base.VannaBase.get_related_ddl]

        - [`get_related_documentation`][vanna.base.base.VannaBase.get_related_documentation]

        - [`get_sql_prompt`][vanna.base.base.VannaBase.get_sql_prompt]

        - [`submit_prompt`][vanna.base.base.VannaBase.submit_prompt]


        Args:
            question (str): The question to generate a SQL query for.
            allow_llm_to_see_data (bool): Whether to allow the LLM to see the data (for the purposes of introspecting the data to generate the final SQL).

        Returns:
            str: The SQL query that answers the question.
        """
        if self.config is not None:
            initial_prompt = self.config.get("initial_prompt", None)
        else:
            initial_prompt = None
        question_sql_list = self.get_similar_question_sql(question, **kwargs)
        ddl_list = self.get_related_ddl(question, **kwargs)
        doc_list = self.get_related_documentation(question, **kwargs)
        prompt = self.get_sql_prompt(
            initial_prompt=initial_prompt,
            question=question,
            question_sql_list=question_sql_list,
            ddl_list=ddl_list,
            doc_list=doc_list,
            **kwargs,
        )
        self.log(title="SQL Prompt", message=prompt)
        llm_response = self.submit_prompt(prompt, **kwargs)
        self.log(title="LLM Response", message=llm_response)

        if "intermediate_sql" in llm_response:
            if not allow_llm_to_see_data:
                return "The LLM is not allowed to see the data in your database. Your question requires database introspection to generate the necessary SQL. Please set allow_llm_to_see_data=True to enable this."

            if allow_llm_to_see_data:
                intermediate_sql = self.extract_sql(llm_response)
                if not self.is_sql_read_only_code(intermediate_sql):
                    return (
                        "Refusing to run intermediate SQL because it is not a read-only "
                        f"SELECT query: {intermediate_sql}"
                    )

                try:
                    self.log(title="Running Intermediate SQL", message=intermediate_sql)
                    df = self.run_sql(intermediate_sql)

                    prompt = self.get_sql_prompt(
                        initial_prompt=initial_prompt,
                        question=question,
                        question_sql_list=question_sql_list,
                        ddl_list=ddl_list,
                        doc_list=doc_list
                        + [
                            f"The following is a pandas DataFrame with the results of the intermediate SQL query {intermediate_sql}: \n"
                            + df.to_markdown()
                        ],
                        **kwargs,
                    )
                    self.log(title="Final SQL Prompt", message=prompt)
                    llm_response = self.submit_prompt(prompt, **kwargs)
                    self.log(title="LLM Response", message=llm_response)
                except Exception as e:
                    return f"Error running intermediate SQL: {e}"

        return self.extract_sql(llm_response)


class VannaClient(QdrantVectorStore, OpenAI_Chat):
    """Project Vanna client using Qdrant retrieval and OpenAI-compatible chat."""

    def __init__(
        self,
        qdrant_config: dict[str, Any] | None = None,
        openai_config: dict[str, Any] | None = None,
        config: dict[str, Any] | None = None,
    ):
        shared_config = deepcopy(config) if config is not None else {}
        qdrant_settings = {**shared_config, **(qdrant_config or {})}
        openai_settings = {**shared_config, **_default_openai_config(), **(openai_config or {})}

        QdrantVectorStore.__init__(self, config=qdrant_settings)

        openai_client = openai_settings.pop("client", None)
        if openai_client is None and openai_settings.get("api_key") and openai_settings.get("base_url"):
            openai_client = OpenAI(
                api_key=openai_settings.get("api_key"),
                base_url=openai_settings["base_url"],
                http_client=httpx.Client(verify=False)
            )

        OpenAI_Chat.__init__(self, client=openai_client, config=openai_settings)

        self.qdrant_config = qdrant_settings
        self.openai_config = openai_settings
        self.config = {**qdrant_settings, **openai_settings}
        self.database_connection_config: dict[str, Any] | None = None


DATABASE_CONNECTORS = {
    "bigquery": "connect_to_bigquery",
    "clickhouse": "connect_to_clickhouse",
    "duckdb": "connect_to_duckdb",
    "hive": "connect_to_hive",
    "mssql": "connect_to_mssql",
    "mysql": "connect_to_mysql",
    "oracle": "connect_to_oracle",
    "postgres": "connect_to_postgres",
    "presto": "connect_to_presto",
    "snowflake": "connect_to_snowflake",
    "sqlite": "connect_to_sqlite",
}


def initialize_vanna(
    qdrant_config: dict[str, Any] | None = None,
    openai_config: dict[str, Any] | None = None,
    db_config: dict[str, Any] | None = None,
    config: dict[str, Any] | None = None,
) -> VannaClient:
    vn = VannaClient(qdrant_config=qdrant_config, openai_config=openai_config, config=config)

    if db_config is not None:
        _connect_database(vn, db_config)

    return vn


def _default_openai_config() -> dict[str, Any]:
    config: dict[str, Any] = {}
    if OPENAI_API_KEY:
        config["api_key"] = OPENAI_API_KEY
    if OPENAI_MODEL:
        config["model"] = OPENAI_MODEL
    if OPENAI_API_URL:
        config["base_url"] = OPENAI_API_URL
    return config


def _connect_database(vn: VannaClient, db_config: dict[str, Any]) -> None:
    db_type = db_config.get("type")
    if not db_type:
        raise ValueError("db_config must contain a non-empty 'type' value.")

    connector_name = DATABASE_CONNECTORS.get(str(db_type).lower())
    if connector_name is None:
        supported = ", ".join(sorted(DATABASE_CONNECTORS))
        raise ValueError(f"Unsupported database type {db_type!r}. Supported: {supported}.")

    params = db_config.get("params", {})
    if params is None:
        params = {}
    if not isinstance(params, dict):
        raise TypeError("db_config['params'] must be a dictionary.")

    connector = getattr(vn, connector_name)
    connector(**params)
    vn.database_connection_config = {
        "type": str(db_type).lower(),
        "connector": connector_name,
        "params": deepcopy(params),
    }


__all__ = [
    "DATABASE_CONNECTORS",
    "VannaClient",
    "QdrantVectorStore",
    "initialize_vanna",
]
