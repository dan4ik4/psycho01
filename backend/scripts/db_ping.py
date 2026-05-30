import os
from sqlalchemy import create_engine, text
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).with_name(".env"))

host = os.getenv("DB_HOST", "localhost")
port = os.getenv("DB_PORT", "5432")
name = os.getenv("DB_NAME", "app")
user = os.getenv("DB_USER", "app")
pwd  = os.getenv("DB_PASS", "app")

url = f"postgresql+psycopg2://{user}:{pwd}@{host}:{port}/{name}"
engine = create_engine(url)

with engine.connect() as conn:
    r = conn.execute(text("select 1")).scalar_one()
    print("DB OK:", r)
