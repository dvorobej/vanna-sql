from __future__ import annotations

DIFFICULTY_RULES = {
    "easy": (
        "Простой запрос: одна таблица, выбор нескольких полей, простые фильтры, "
        "сортировка, LIMIT или простая агрегация без сложных соединений."
    ),
    "medium": (
        "Средний запрос: соединение 2-3 таблиц, группировки, агрегаты, фильтры по датам, "
        "условные выражения или расчетные поля."
    ),
    "hard": (
        "Сложный запрос: CTE, подзапросы, оконные функции, несколько соединений, "
        "многошаговая бизнес-логика или сравнение агрегированных результатов."
    ),
}

QUERY_DESCRIPTION_REWRITE_STYLES = {
    "short": (
        "Короткое описание задачи скрипта: одно прямое предложение в стиле "
        "'Скрипт для ...', без лишнего контекста."
    ),
    "business": (
        "Бизнес-описание задачи скрипта: опиши банковскую цель, операционный смысл, "
        "контекст мониторинга клиентов, счетов или транзакций. Формулировка должна "
        "звучать как назначение аналитического скрипта, а не как команда пользователю."
    ),
    "technical": (
        "Техническое описание задачи скрипта: уточни фильтры, группировки, сортировки, "
        "агрегации, даты или форму результата, но не пиши SQL. Формулировка должна "
        "описывать алгоритм получения результата."
    ),
}


def build_query_description_prompt(
    schema_description: str,
    difficulty: str,
    database_name: str,
) -> list[dict[str, str]]:
    difficulty_rule = _difficulty_rule(difficulty)
    return [
        {
            "role": "system",
            "content": (
                "Ты помогаешь подготовить датасет для обучения text-to-SQL системы. "
                "Все ответы должны быть на русском языке."
            ),
        },
        {
            "role": "user",
            "content": (
                f"База данных: {database_name}\n\n"
                "Ниже приведена схема базы данных с комментариями и примерами первых строк:\n"
                f"{schema_description}\n\n"
                "Нужно придумать ровно одно описание аналитического SQL-запроса на естественном "
                "русском языке.\n"
                f"Сложность: {difficulty}\n"
                f"Правила сложности: {difficulty_rule}\n\n"
                "Требования:\n"
                "- Верни только одно описание запроса.\n"
                "- Не пиши SQL-код.\n"
                "- Не добавляй нумерацию, markdown, пояснения или кавычки.\n"
                "- Описание должно быть реалистичным для банковского мониторинга транзакций."
            ),
        },
    ]


def build_sql_generation_prompt(
    schema_description: str,
    query: str,
    difficulty: str,
) -> list[dict[str, str]]:
    difficulty_rule = _difficulty_rule(difficulty)
    return [
        {
            "role": "system",
            "content": (
                "Ты эксперт по SQLite. Генерируй только безопасные read-only SQL-запросы. "
                "Не изменяй данные и не используй DDL/DML."
            ),
        },
        {
            "role": "user",
            "content": (
                "Ниже приведена схема базы данных с комментариями и примерами первых строк:\n"
                f"{schema_description}\n\n"
                f"Описание запроса: {query}\n"
                f"Сложность: {difficulty}\n"
                f"Правила сложности: {difficulty_rule}\n\n"
                "Сгенерируй SQL для SQLite.\n"
                "Требования:\n"
                "- Верни только SQL-код, без пояснений.\n"
                "- Используй только таблицы и поля из схемы.\n"
                "- Запрос должен быть read-only и возвращать строки.\n"
                "- Если используешь markdown, помести SQL только в блок ```sql."
            ),
        },
    ]


def build_related_query_description_prompt(
    schema_description: str,
    query_description: str,
    style: str,
    difficulty: str | None = None,
) -> list[dict[str, str]]:
    style_rule = _rewrite_style_rule(style)
    difficulty_text = ""
    if difficulty is not None:
        difficulty_text = (
            f"\nСложность исходного запроса: {difficulty}\n"
            f"Правила сложности: {_difficulty_rule(difficulty)}"
        )

    return [
        {
            "role": "system",
            "content": (
                "Ты помогаешь расширять датасет для text-to-SQL системы, создавая "
                "связанные вариации описаний аналитических запросов. "
                "Все ответы должны быть на русском языке."
            ),
        },
        {
            "role": "user",
            "content": (
                "Ниже приведена схема базы данных с комментариями и примерами первых строк:\n"
                f"{schema_description}\n\n"
                f"Исходное описание запроса: {query_description}"
                f"{difficulty_text}\n"
                f"Нужный стиль формулировки: {style}\n"
                f"Правила стиля: {style_rule}\n\n"
                "Придумай новое описание аналитического запроса, которое:\n"
                "- остаётся семантически связанным с исходным (та же предметная область, "
                "похожие таблицы и тип анализа);\n"
                "- не является дословной копией исходного описания;\n"
                "- допускает перефразирование, изменение лимитов, фильтров, группировок "
                "или смежный аналитический угол в рамках той же задачи;\n"
                "- могло бы привести к SQL, близкому или родственному исходному запросу.\n\n"
                "Требования:\n"
                "- Верни ровно одно новое описание запроса в указанном стиле.\n"
                "- Сохрани уровень сложности исходного запроса.\n"
                "- Не пиши SQL-код.\n"
                "- Не добавляй markdown, нумерацию, кавычки или пояснения.\n"
                "- Используй схему только как контекст для точной терминологии."
            ),
        },
    ]


def build_query_description_rewrite_prompt(
    schema_description: str,
    query_description: str,
    rewrite_style: str,
    difficulty: str | None = None,
) -> list[dict[str, str]]:
    style_rule = _rewrite_style_rule(rewrite_style)
    difficulty_text = ""
    if difficulty is not None:
        difficulty_text = f"\nСложность исходного запроса: {difficulty}"

    return [
        {
            "role": "system",
            "content": (
                "Ты редактируешь описания SQL-скриптов для text-to-SQL датасета. "
                "Результат должен звучать как описание алгоритма или назначения скрипта, "
                "а не как пользовательская команда на выполнение запроса. "
                "Все ответы должны быть на русском языке."
            ),
        },
        {
            "role": "user",
            "content": (
                "Ниже приведена схема базы данных с комментариями и примерами первых строк:\n"
                f"{schema_description}\n\n"
                f"Исходное описание запроса: {query_description}"
                f"{difficulty_text}\n"
                f"Нужный формат переписывания: {rewrite_style}\n"
                f"Правила формата: {style_rule}\n\n"
                "Преобразуй императивные формулировки в описания задач скрипта:\n"
                "- Вместо 'Показать топ 10 последних операций...' пиши "
                "'Поиск топ 10 последних операций, отсортированных по ...'.\n"
                "- Вместо 'Рассчитать показатель за период...' пиши "
                "'Алгоритм для расчета показателя за период ...'.\n"
                "- Вместо 'Вывести клиентов...' пиши "
                "'Скрипт для формирования списка клиентов ...'.\n\n"
                "Требования:\n"
                "- Верни ровно одно переписанное описание задачи скрипта.\n"
                "- Начинай формулировку со слов 'Скрипт для', 'Алгоритм', 'Расчет', 'Поиск', или близкой конструкции "
                "описания назначения, если это звучит естественно.\n"
                "- Сохрани исходный аналитический смысл и уровень сложности.\n"
                "- Не пиши SQL-код.\n"
                "- Не добавляй markdown, нумерацию, кавычки или пояснения.\n"
                "- Используй схему только как контекст для точной терминологии."
            ),
        },
    ]


def _difficulty_rule(difficulty: str) -> str:
    try:
        return DIFFICULTY_RULES[difficulty]
    except KeyError as exc:
        supported = ", ".join(sorted(DIFFICULTY_RULES))
        raise ValueError(f"Unknown difficulty={difficulty!r}. Supported: {supported}.") from exc


def _rewrite_style_rule(rewrite_style: str) -> str:
    try:
        return QUERY_DESCRIPTION_REWRITE_STYLES[rewrite_style]
    except KeyError as exc:
        supported = ", ".join(sorted(QUERY_DESCRIPTION_REWRITE_STYLES))
        raise ValueError(
            f"Unknown rewrite_style={rewrite_style!r}. Supported: {supported}."
        ) from exc
