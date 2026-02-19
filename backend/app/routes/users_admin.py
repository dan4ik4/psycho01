from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.permissions import require_owner, require_owner_or_psychologist
from app.db.deps import get_db
from app.models.user import User
from app.schemas.user import UserRead, UserAdminUpdate

router = APIRouter(prefix="/users", tags=["admin-users"])


@router.get("/{id}", response_model=UserRead, summary="Get user by id (psychologist/owner)")
async def get_user_by_id(
    id: UUID,
    _: User = Depends(require_owner_or_psychologist),
    session: AsyncSession = Depends(get_db),
):
    res = await session.execute(select(User).where(User.id == id))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user


@router.patch("/{id}", response_model=UserRead, summary="Update user by id (owner)")
async def update_user_by_id(
    id: UUID,
    data: UserAdminUpdate,
    _: User = Depends(require_owner),
    session: AsyncSession = Depends(get_db),
):
    res = await session.execute(select(User).where(User.id == id))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    if data.email is not None:
        email_exists = await session.execute(
            select(User.id).where(User.email == data.email, User.id != id)
        )
        if email_exists.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already in use")
        user.email = data.email

    if data.is_active is not None:
        user.is_active = data.is_active

    if data.role is not None:
        user.role = data.role

    await session.commit()
    await session.refresh(user)
    return user


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete user by id (owner)")
async def delete_user_by_id(
    id: UUID,
    _: User = Depends(require_owner),
    session: AsyncSession = Depends(get_db),
):
    res = await session.execute(select(User).where(User.id == id))
    user = res.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    await session.delete(user)
    await session.commit()
    return None