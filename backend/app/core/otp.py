import hashlib
import secrets


def generate_code6() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_code(code: str, secret: str) -> str:
    # хэшируем код + секрет, чтобы нельзя было перебором по БД
    return hashlib.sha256((code + secret).encode("utf-8")).hexdigest()