import uuid

from fastapi import (
    APIRouter,
    Body,
    Depends,
    HTTPException,
    Request,
    status,
)
from fastapi_users import exceptions
from fastapi_users.manager import BaseUserManager
from fastapi_users.router.common import ErrorCode, ErrorModel
from pydantic import EmailStr

from app.auth.deps import get_user_manager
from app.core.email import normalize_email
from app.core.rate_limiter import limiter
from app.core.settings import settings
from app.models.user import User

router = APIRouter(
    prefix="/auth",
    tags=["auth"],
)

reset_password_responses = {
    status.HTTP_400_BAD_REQUEST: {
        "model": ErrorModel,
        "content": {
            "application/json": {
                "examples": {
                    ErrorCode.RESET_PASSWORD_BAD_TOKEN: {
                        "summary": "Bad or expired token",
                        "value": {
                            "detail": ErrorCode.RESET_PASSWORD_BAD_TOKEN,
                        },
                    },
                    ErrorCode.RESET_PASSWORD_INVALID_PASSWORD: {
                        "summary": "Password validation failed",
                        "value": {
                            "detail": {
                                "code": (ErrorCode.RESET_PASSWORD_INVALID_PASSWORD),
                                "reason": ("Password should be at least 8 characters"),
                            },
                        },
                    },
                },
            },
        },
    },
}


async def get_forgot_password_email(
    request: Request,
    email: EmailStr = Body(..., embed=True),
) -> EmailStr:
    request.state.forgot_password_email = normalize_email(
        str(email),
    )

    return email


def get_forgot_password_email_key(
    request: Request,
) -> str:
    return request.state.forgot_password_email


@router.post(
    "/forgot-password",
    status_code=status.HTTP_202_ACCEPTED,
    name="reset:forgot_password",
    description="Accepts email. Sends an oakle://reset-password?token=... link for an active account. Returns 202 even for an unknown email. Token lifetime: 1 hour.",
)
@limiter.limit(
    settings.AUTH_FORGOT_PASSWORD_IP_RATE_LIMIT,
)
@limiter.limit(
    settings.AUTH_FORGOT_PASSWORD_EMAIL_RATE_LIMIT,
    key_func=get_forgot_password_email_key,
)
async def forgot_password(
    request: Request,
    email: EmailStr = Depends(
        get_forgot_password_email,
    ),
    user_manager: BaseUserManager[User, uuid.UUID] = Depends(
        get_user_manager,
    ),
) -> None:
    try:
        user = await user_manager.get_by_email(email)
    except exceptions.UserNotExists:
        return

    try:
        await user_manager.forgot_password(
            user,
            request,
        )
    except exceptions.UserInactive:
        pass

    return


@router.post(
    "/reset-password",
    name="reset:reset_password",
    description="Accepts token and password (minimum 8 characters). Successful reset invalidates this token. Invalid/expired token: 400 RESET_PASSWORD_BAD_TOKEN.",
    responses=reset_password_responses,
)
async def reset_password(
    request: Request,
    token: str = Body(...),
    password: str = Body(...),
    user_manager: BaseUserManager[User, uuid.UUID] = Depends(
        get_user_manager,
    ),
) -> None:
    try:
        await user_manager.reset_password(
            token,
            password,
            request,
        )

    except (
        exceptions.InvalidResetPasswordToken,
        exceptions.UserNotExists,
        exceptions.UserInactive,
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ErrorCode.RESET_PASSWORD_BAD_TOKEN,
        )

    except exceptions.InvalidPasswordException as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": ErrorCode.RESET_PASSWORD_INVALID_PASSWORD,
                "reason": error.reason,
            },
        )
