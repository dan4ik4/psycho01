"""Run local commands using isolated, ignored .env.local (never production .env)."""

import os
import subprocess
import sys
from pathlib import Path

from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parents[1]


def local_environment():
    path = ROOT / ".env.local"
    if not path.exists():
        raise SystemExit("Create backend/.env.local from .env.example first")
    env = os.environ.copy()
    env.update({k: v for k, v in dotenv_values(path).items() if v is not None})
    if (
        env.get("DB_HOST") not in ("127.0.0.1", "localhost")
        or env.get("TEST_MODE", "").lower() != "true"
    ):
        raise SystemExit("Local runner requires a loopback database and TEST_MODE=true")
    env["PYTHONUTF8"] = "1"
    env["PSYCHO_ENV_FILE"] = str(path)
    return env


if __name__ == "__main__":
    commands = {
        "migrate": ["-m", "alembic", "upgrade", "head"],
        "serve": [
            "-m",
            "uvicorn",
            "app.main:app",
            "--host",
            "127.0.0.1",
            "--port",
            "8000",
        ],
        "test": ["scripts/run_tests.py"],
    }
    name = sys.argv[1] if len(sys.argv) > 1 else "serve"
    args = commands.get(name, sys.argv[1:])
    raise SystemExit(
        subprocess.call([sys.executable, *args], cwd=ROOT, env=local_environment())
    )
