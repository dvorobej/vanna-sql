import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from .env file if it exists
load_dotenv()

# Paths
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"
RAW_DATA_DIR = DATA_DIR / "raw"
INTERIM_DATA_DIR = DATA_DIR / "interim"
PROCESSED_DATA_DIR = DATA_DIR / "processed"
EXTERNAL_DATA_DIR = DATA_DIR / "external"

MODELS_DIR = PROJECT_ROOT / "models"

REPORTS_DIR = PROJECT_ROOT / "reports"
FIGURES_DIR = REPORTS_DIR / "figures"

QDRANT_URL = os.getenv("QDRANT_URL")
QDRANT_API_KEY = os.getenv("QDRANT_API_KEY")

DENSE_EMBEDDING_MODEL = os.getenv("DENSE_EMBEDDING_MODEL")
DENSE_EMBEDDING_MODEL_PATH = os.path.join(MODELS_DIR, DENSE_EMBEDDING_MODEL)

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_API_URL = os.getenv("OPENAI_API_URL", "https://openrouter.ai/api/v1")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "openai/gpt-5.5")
OPENAI_MODEL_MINI = os.getenv("OPENAI_MODEL_MINI", "openai/gpt-5.4-nano")
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek/deepseek-v4-flash")
QWEN_37_PLUS = os.getenv("QWEN_37_PLUS", "qwen/qwen3.7-plus")
GEMMA_4_31B = os.getenv("GEMMA_4_31B", "google/gemma-4-31b-it")
GEMINI_31_FLASH_LITE = os.getenv("GEMINI_3_1_FLASH_LITE", "google/gemini-3.1-flash-lite")

DEVICE = os.getenv("DEVICE", "cpu")