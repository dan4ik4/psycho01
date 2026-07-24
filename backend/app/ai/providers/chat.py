from typing import Literal, TypedDict

from openai import AsyncOpenAI, OpenAIError

from app.core.settings import settings


class ChatMessage(TypedDict):
    role: Literal["user", "assistant"]
    content: str


class AiProviderError(RuntimeError):
    pass


SYSTEM_INSTRUCTIONS = """
You are a supportive mental health assistant.

Respond in the same language as the user.
Be calm, empathetic, and practical.
Do not diagnose medical or psychiatric conditions.
Do not prescribe medication.
Do not claim to replace a psychologist, psychiatrist, or emergency service.

If the user indicates an immediate risk of harming themselves or another
person, clearly encourage them to contact local emergency services and a
trusted person nearby.
""".strip()


openai_client = AsyncOpenAI(
    api_key=settings.OPENAI_API_KEY,
    timeout=30.0,
    max_retries=2,
)


async def generate_ai_reply(
    messages: list[ChatMessage],
) -> str:
    if not messages:
        raise ValueError("Message history cannot be empty")

    if settings.AI_MOCK_MODE:
        last_user_message = next(
            (
                message["content"]
                for message in reversed(messages)
                if message["role"] == "user"
            ),
            "",
        )

        return (
            "Это тестовый ответ AI. "
            f"Последнее сообщение пользователя: {last_user_message}"
        )

    try:
        response = await openai_client.responses.create(
            model=settings.OPENAI_MODEL,
            instructions=SYSTEM_INSTRUCTIONS,
            input=messages,
            max_output_tokens=settings.OPENAI_MAX_OUTPUT_TOKENS,
        )

    except OpenAIError as error:
        raise AiProviderError(
            "AI provider is currently unavailable"
        ) from error

    reply = response.output_text.strip()

    if not reply:
        raise AiProviderError(
            "AI provider returned an empty response"
        )

    return reply