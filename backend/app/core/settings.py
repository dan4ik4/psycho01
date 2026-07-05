from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DB_HOST: str
    DB_PORT: int
    DB_NAME: str
    DB_USER: str
    DB_PASS: str
    JWT_SECRET: str = "SUPERSECRET"

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

    FRONTEND_URL: str = "http://localhost:3000"

    DEBUG: bool = True


    @property
    def DATABASE_URL(self) -> str:
        return f"postgresql+asyncpg://{self.DB_USER}:{self.DB_PASS}@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
