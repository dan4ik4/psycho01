from pydantic_settings import BaseSettings
from sqlalchemy import URL

class Settings(BaseSettings):
    DB_HOST: str
    DB_PORT: int
    DB_NAME: str
    DB_USER: str
    DB_PASS: str
    JWT_SECRET: str

    REG_CODE_SECRET: str
    REG_CODE_TTL_MINUTES: int = 10
    REG_CODE_MAX_ATTEMPTS: int = 5
    REG_CODE_MAX_RESENDS: int = 3
    REG_CODE_RESEND_COOLDOWN_SECONDS: int = 60
    REG_PENDING_CLEANUP_HOURS: int = 12

    AGORA_APP_ID: str
    AGORA_APP_CERTIFICATE: str
    AGORA_JOIN_WINDOW_MINUTES: int = 5

    RESEND_API_KEY: str
    RESEND_FROM_EMAIL: str

    OPENAI_API_KEY: str | None = None
    OPENAI_MODEL: str = "gpt-5-mini"
    OPENAI_MAX_OUTPUT_TOKENS: int = 800
    OPENAI_HISTORY_MESSAGE_LIMIT: int = 40
    OPENAI_MESSAGE_MAX_LENGTH: int = 10000

    AI_MOCK_MODE: bool = False

    FRONTEND_URL: str = "http://localhost:3000"

    DEBUG: bool = False


    @property
    def DATABASE_URL(self) -> URL:
        return URL.create(
            drivername="postgresql+asyncpg",
            username=self.DB_USER,
            password=self.DB_PASS,
            host=self.DB_HOST,
            port=self.DB_PORT,
            database=self.DB_NAME,
        )

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
