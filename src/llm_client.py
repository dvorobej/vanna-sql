from __future__ import annotations

import time
from typing import Any

DEFAULT_LLM_TIMEOUT_SEC = 180
DEFAULT_LLM_MAX_RETRIES = 3
DEFAULT_LLM_RETRY_DELAY_SEC = 2.0


def extract_response_text(response: Any) -> str:
    choice = response.choices[0]
    if isinstance(choice, dict):
        message = choice.get("message", {})
        content = message.get("content", choice.get("text"))
    elif hasattr(choice, "message") and hasattr(choice.message, "content"):
        content = choice.message.content
    elif hasattr(choice, "text"):
        content = choice.text
    else:
        raise ValueError("Could not extract text from OpenAI-compatible response.")

    if content is None:
        return ""
    return str(content).strip()


def call_openai_chat_with_retries(
    client: Any,
    model: str,
    messages: list[dict[str, str]],
    temperature: float,
    *,
    timeout: float = DEFAULT_LLM_TIMEOUT_SEC,
    max_retries: int = DEFAULT_LLM_MAX_RETRIES,
    retry_delay_sec: float = DEFAULT_LLM_RETRY_DELAY_SEC,
) -> str:
    last_error: Exception | None = None

    for attempt in range(max_retries + 1):
        try:
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
                timeout=timeout,
            )
            text = extract_response_text(response)
            if text:
                return text
            last_error = ValueError("LLM returned empty content.")
        except Exception as exc:
            last_error = exc

        if attempt < max_retries:
            time.sleep(retry_delay_sec * (attempt + 1))

    raise RuntimeError(
        f"LLM request failed after {max_retries + 1} attempts for model={model!r}."
    ) from last_error
