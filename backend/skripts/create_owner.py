import os
import sys
from pathlib import Path
from dotenv import load_dotenv

sys.path.append(str(Path(__file__).resolve().parent))
load_dotenv(Path(__file__).with_name(".env"))

from getpass import getpass
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from fastapi_users.password import PasswordHelper

# берём те же переменные, что и в .env
host = os.getenv("DB_HOST", "localhost")
port = os.getenv("DB_PORT", "5432")
name = os.getenv("DB_NAME", "app")
user = os.getenv("DB_USER", "app")
pwd  = os.getenv("DB_PASS", "app")
url  = f"postgresql+psycopg2://{user}:{pwd}@{host}:{port}/{name}"

print("DB_URL =", url)

engine = create_engine(url, future=True)

from app.models.user import User, Role

password_helper = PasswordHelper()

def main():
    email = input("Email владельца: ").strip().lower()
    password = getpass("Пароль: ").strip()

    with Session(engine) as s:
        exists = s.execute(select(User).where(User.email == email)).scalar_one_or_none()
        if exists:
            print("Пользователь с таким email уже есть.")
            return

        u = User(
            email=email,
            password_hash=password_helper.hash(password),
            role=Role.OWNER,
            is_active=True\
        )
        s.add(u)
        s.commit()
        print("OK: создан владелец с email =", email)

if __name__ == "__main__":
    main()