from uuid import UUID

from fastapi import APIRouter, Depends, status
from fastapi_users.manager import BaseUserManager

from app.auth.deps import current_active_user, get_user_manager
from app.models.user import User
from app.schemas.user import UserRead, UserUpdateSelf

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserRead)
async def read_me(user: User = Depends(current_active_user)):
    return user


@router.patch("/me", response_model=UserRead)
async def update_me(
    data: UserUpdateSelf,
    user: User = Depends(current_active_user),
    manager: BaseUserManager[User, UUID] = Depends(get_user_manager),
):
    return await manager.update(user, data)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(
    user: User = Depends(current_active_user),
    manager: BaseUserManager[User, UUID] = Depends(get_user_manager),
):
    await manager.delete(user)
    return None