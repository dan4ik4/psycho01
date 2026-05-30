import hashlib
import secrets
import hmac


def generate_code6() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_code(code: str, secret: str) -> str:
    return hmac.new(
        secret.encode(),
        code.encode(),
        hashlib.sha256
    ).hexdigest()
    
def verify_code(input_code: str, stored_hash: str, secret: str) -> bool:
    return hmac.compare_digest(
        hash_code(input_code, secret),
        stored_hash
    )