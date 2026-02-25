import uuid
from typing import AsyncGenerator

from fastapi import Depends
from fastapi_users import FastAPIUsers
from fastapi_users.authentication import AuthenticationBackend, BearerTransport, JWTStrategy
from fastapi_users.db import SQLAlchemyUserDatabase
from fastapi_users.jwt import SecretType
from fastapi_users.manager import BaseUserManager, UUIDIDMixin
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.requests import Request
from fastapi import HTTPException, status

from app.core.settings import settings
from app.db.deps import get_db
from app.models.user import User
from app.core.mailer import send_email


# -------- user db --------
async def get_user_db(session: AsyncSession = Depends(get_db)):
    yield SQLAlchemyUserDatabase(session, User)


# -------- user manager --------
class UserManager(UUIDIDMixin, BaseUserManager[User, uuid.UUID]):
    reset_password_token_secret: SecretType = settings.JWT_SECRET
    verification_token_secret: SecretType = settings.JWT_SECRET

    async def on_after_register(self, user: User, request: Request | None = None):
        return
    
    async def on_after_forgot_password(
        self, user: User, token: str, request: Request | None = None
    ):
        reset_link = f"{settings.FRONTEND_URL}/reset-password?token={token}"

        await send_email(
            to=user.email,
            subject="Сброс пароля",
            text=(
                f"Чтобы сбросить пароль, перейдите по ссылке:\n\n"
                f"{reset_link}\n\n"
                "Если вы не запрашивали сброс — просто проигнорируйте письмо."
            ),
        )
    
    async def validate_password(
        self,
        password: str,
        user: User | None = None,
    ) -> None:
        if len(password) < 8:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Пароль должен содержать минимум 8 символов",
            )


async def get_user_manager(user_db=Depends(get_user_db)):
    yield UserManager(user_db)




# -------- auth backend --------
bearer_transport = BearerTransport(tokenUrl="/api/v1/auth/jwt/login")


def get_jwt_strategy() -> JWTStrategy:
    return JWTStrategy(secret=settings.JWT_SECRET, lifetime_seconds=60 * 60 * 24)


auth_backend = AuthenticationBackend(
    name="jwt",
    transport=bearer_transport,
    get_strategy=get_jwt_strategy,
)


# -------- FastAPI Users instance + deps --------
fastapi_users = FastAPIUsers[User, uuid.UUID](
    get_user_manager,
    [auth_backend],
)

current_active_user = fastapi_users.current_user(active=True)