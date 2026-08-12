import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_superuser
from app.db.deps import get_db
from app.models.user import User
from app.schemas.user import UserRead
from app.services.admin import toggle_psychologist


router = APIRouter(
    prefix="/admin",
    tags=["admin"],
)


@router.patch(
    "/users/{user_id}/psychologist",
    response_model=UserRead,
)
async def toggle_psychologist_endpoint(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_superuser),
) -> User:
    return await toggle_psychologist(
        db=db,
        user_id=user_id,
    )