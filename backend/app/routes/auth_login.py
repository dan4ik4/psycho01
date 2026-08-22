import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
from fastapi_users.authentication import Strategy
from fastapi_users.manager import BaseUserManager
from fastapi_users.router.common import ErrorCode, ErrorModel

from app.auth.deps import auth_backend, fastapi_users, get_user_manager
from app.core.rate_limiter import limiter
from app.core.settings import settings
from app.models.user import User


router = APIRouter(prefix="/auth/jwt", tags=["auth"])

get_current_user_token = fastapi_users.authenticator.current_user_token(
    active=True,
)

login_responses = {
    status.HTTP_400_BAD_REQUEST: {
        "model": ErrorModel,
        "content": {
            "application/json": {
                "examples": {
                    ErrorCode.LOGIN_BAD_CREDENTIALS: {
                        "summary": "Bad credentials or inactive user",
                        "value": {
                            "detail": ErrorCode.LOGIN_BAD_CREDENTIALS,
                        },
                    },
                },
            },
        },
    },
    **auth_backend.transport.get_openapi_login_responses_success(),
}

logout_responses = {
    status.HTTP_401_UNAUTHORIZED: {
        "description": "Missing token or inactive user",
    },
    **auth_backend.transport.get_openapi_logout_responses_success(),
}


@router.post(
    "/login",
    name="auth:jwt.login",
    responses=login_responses,
)
@limiter.limit(settings.AUTH_LOGIN_RATE_LIMIT)
async def login(
    request: Request,
    credentials: OAuth2PasswordRequestForm = Depends(),
    user_manager: BaseUserManager[User, uuid.UUID] = Depends(
        get_user_manager,
    ),
    strategy: Strategy[User, uuid.UUID] = Depends(
        auth_backend.get_strategy,
    ),
):
    user = await user_manager.authenticate(credentials)

    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ErrorCode.LOGIN_BAD_CREDENTIALS,
        )

    response = await auth_backend.login(
        strategy,
        user,
    )

    await user_manager.on_after_login(
        user,
        request,
        response,
    )

    return response


@router.post(
    "/logout",
    name="auth:jwt.logout",
    responses=logout_responses,
)
async def logout(
    user_token: tuple[User, str] = Depends(
        get_current_user_token,
    ),
    strategy: Strategy[User, uuid.UUID] = Depends(
        auth_backend.get_strategy,
    ),
):
    user, token = user_token

    return await auth_backend.logout(
        strategy,
        user,
        token,
    )