import sys
from logging.config import fileConfig
from pathlib import Path

from alembic import context
from pydantic_settings import BaseSettings
from sqlalchemy import URL, engine_from_config, pool

sys.path.append(
    str(Path(__file__).resolve().parents[1])
)

from app.db.base import Base
import app.models
import app.ai.models


class AlembicDatabaseSettings(BaseSettings):
    DB_HOST: str
    DB_PORT: int
    DB_NAME: str
    DB_USER: str
    DB_PASS: str

    class Config:
        env_file = ".env"
        extra = "ignore"


db_settings = AlembicDatabaseSettings()

config = context.config

db_url = URL.create(
    drivername="postgresql+psycopg2",
    username=db_settings.DB_USER,
    password=db_settings.DB_PASS,
    host=db_settings.DB_HOST,
    port=db_settings.DB_PORT,
    database=db_settings.DB_NAME,
).render_as_string(
    hide_password=False,
)

config.set_main_option(
    "sqlalchemy.url",
    db_url.replace("%", "%%"),
)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option(
        "sqlalchemy.url",
    )

    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(
            config.config_ini_section,
        ),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()