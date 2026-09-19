"""Run tests in a new PostgreSQL database and remove it even after failure.

Only DB_* values are read from --env-file. Provider credentials are not inherited.
Requires a loopback database server and CREATEDB permission.
"""
import argparse
import os
import secrets
import subprocess
import sys
import uuid
from pathlib import Path

import psycopg2
from dotenv import dotenv_values
from psycopg2 import sql

ROOT = Path(__file__).resolve().parents[1]
DB_KEYS = ("DB_HOST", "DB_PORT", "DB_USER", "DB_PASS", "DB_NAME")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", type=Path)
    args, pytest_args = parser.parse_known_args()
    if args.env_file and not args.env_file.is_file():
        parser.error("The requested environment file does not exist")
    source = dotenv_values(args.env_file) if args.env_file else os.environ
    if any(not source.get(key) for key in DB_KEYS):
        parser.error("Provide all DB_* settings through the environment or --env-file")
    if source["DB_HOST"] not in ("127.0.0.1", "localhost"):
        parser.error("Tests require a loopback PostgreSQL server")
    database = "psycho01_test_" + uuid.uuid4().hex[:12]
    if database == source["DB_NAME"]:
        raise RuntimeError("Refusing to use the application database")
    env = {
        key: value for key, value in os.environ.items()
        if key.upper() in {
            "PATH", "SYSTEMROOT", "WINDIR", "COMSPEC", "PATHEXT", "TEMP", "TMP",
            "HOME", "USERPROFILE", "LANG", "LC_ALL", "VIRTUAL_ENV",
        }
    }
    env.update({key: str(source[key]) for key in DB_KEYS})
    env.update(
        DB_NAME=database, PSYCHO_TEST_DATABASE=database,
        TEST_MODE="true", SCHEDULER_ENABLED="false", BILLING_LIVE_ENABLED="false",
        JWT_SECRET=secrets.token_urlsafe(48),
        REG_CODE_SECRET=secrets.token_urlsafe(48),
        PYTHONUTF8="1", PYTHONDONTWRITEBYTECODE="1",
    )
    connection = psycopg2.connect(
        host=source["DB_HOST"], port=source["DB_PORT"],
        user=source["DB_USER"], password=source["DB_PASS"],
        dbname="postgres", connect_timeout=10,
    )
    connection.autocommit = True
    created = False
    try:
        with connection.cursor() as cursor:
            cursor.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(database)))
        created = True
        print("Created disposable test database: " + database, flush=True)
        absent_env = ROOT / ("." + database + ".env")
        if absent_env.exists():
            raise RuntimeError("Test environment path must not exist")
        env["PSYCHO_ENV_FILE"] = str(absent_env)
        return subprocess.call(
            [sys.executable, "-m", "pytest", "-q", *pytest_args],
            cwd=ROOT, env=env,
        )
    finally:
        try:
            if created:
                with connection.cursor() as cursor:
                    cursor.execute(
                        sql.SQL("DROP DATABASE {} WITH (FORCE)").format(
                            sql.Identifier(database)
                        )
                    )
                print("Removed disposable test database: " + database, flush=True)
        finally:
            connection.close()


if __name__ == "__main__":
    raise SystemExit(main())
