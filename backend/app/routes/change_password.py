from __future__ import annotations

from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException, status

from app.auth.deps import get_user_manager
from app.auth.deps import fastapi_users  # если у тебя этот объект тут лежит
from app.models.user import User  # поправь импорт под твой путь

router = APIRouter()

current_user = fastapi_users.current_user(active=True)


class ChangePasswordIn(BaseModel):
    current_password: str
    new_password: str


@router.post("/auth/change-password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    payload: ChangePasswordIn,
    user: User = Depends(current_user),
    user_manager=Depends(get_user_manager),
):
    # 1) check current password
    valid, _ = user_manager.password_helper.verify_and_update(
        payload.current_password,
        user.hashed_password,
    )
    if not valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid current password",
        )

    # 2) validate new password (твоя validate_password >= 8 сработает)
    await user_manager.validate_password(payload.new_password, user)

    # 3) set new password hash
    user.hashed_password = user_manager.password_helper.hash(payload.new_password)

    await user_manager.user_db.update(user, {"hashed_password": user.hashed_password})

    return None