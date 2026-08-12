from openai import AsyncOpenAI

from app.core.settings import settings


_openai_client: AsyncOpenAI | None = None


def get_openai_client() -> AsyncOpenAI:
    global _openai_client

    if _openai_client is None:
        if not settings.OPENAI_API_KEY:
            raise RuntimeError(
                "OPENAI_API_KEY is not configured"
            )

        _openai_client = AsyncOpenAI(
            api_key=settings.OPENAI_API_KEY,
            timeout=30.0,
            max_retries=2,
        )

    return _openai_client


async def close_openai_client() -> None:
    global _openai_client

    if _openai_client is None:
        return

    await _openai_client.close()
    _openai_client = None