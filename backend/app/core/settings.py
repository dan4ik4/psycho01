import os
from zoneinfo import ZoneInfo
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
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

    AUTH_PREREGISTER_RATE_LIMIT: str = "3/minute"
    AUTH_CONFIRM_RATE_LIMIT: str = "10/minute"
    AUTH_RESEND_RATE_LIMIT: str = "3/minute"
    AUTH_LOGIN_RATE_LIMIT: str = "5/minute"
    AUTH_FORGOT_PASSWORD_IP_RATE_LIMIT: str = "10/minute"
    AUTH_FORGOT_PASSWORD_EMAIL_RATE_LIMIT: str = "3/hour"

    AGORA_APP_ID: str = ""
    AGORA_APP_CERTIFICATE: str = ""
    AGORA_JOIN_WINDOW_MINUTES: int = 5

    RESEND_API_KEY: str = ""
    RESEND_FROM_EMAIL: str = ""

    OPENAI_API_KEY: str | None = None
    OPENAI_MODEL: str = "gpt-5-mini"
    OPENAI_MAX_OUTPUT_TOKENS: int = 800
    OPENAI_HISTORY_MESSAGE_LIMIT: int = 40
    OPENAI_MESSAGE_MAX_LENGTH: int = 10000

    TEST_MODE: bool = False
    SCHEDULER_ENABLED: bool = True
    BILLING_CURRENCY: str = "RUB"
    BILLING_TIMEZONE: str = "Europe/Moscow"
    AI_FREE_DAILY_LIMIT: int = Field(default=3, ge=0)
    SUBSCRIPTION_PRICE_MINOR: int = Field(default=99000, gt=0)
    SUBSCRIPTION_DAYS: int = Field(default=30, ge=1, le=366)
    BOOKING_HOLD_MINUTES: int = Field(default=15, ge=1, le=60)
    # Basis points of the gross charge. Unset rates prevent live checkout.
    BILLING_TAX_BPS: int | None = Field(default=None, ge=0, lt=10000)
    BILLING_PLATFORM_FEE_BPS: int | None = Field(default=None, ge=0, lt=10000)
    BILLING_PROCESSOR_FEE_BPS: int | None = Field(default=None, ge=0, lt=10000)
    BILLING_PROCESSOR_FIXED_MINOR: int | None = Field(default=None, ge=0)
    STRIPE_SECRET_KEY: str = ""
    STRIPE_WEBHOOK_SECRET: str = ""
    STRIPE_CONNECT_COUNTRY: str = ""
    REVENUECAT_SECRET_KEY: str = ""
    REVENUECAT_WEBHOOK_TOKEN: str = ""
    REVENUECAT_ENTITLEMENT: str = "paid_ai"
    BILLING_LIVE_ENABLED: bool = False

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

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @field_validator("BILLING_TIMEZONE")
    @classmethod
    def timezone_exists(cls, value: str) -> str:
        ZoneInfo(value)
        return value

    @field_validator("BILLING_CURRENCY")
    @classmethod
    def currency_code(cls, value: str) -> str:
        if len(value) != 3 or not value.isalpha():
            raise ValueError("Use a three-letter currency code")
        return value.upper()

settings = Settings(_env_file=os.environ.get("PSYCHO_ENV_FILE", ".env"))
