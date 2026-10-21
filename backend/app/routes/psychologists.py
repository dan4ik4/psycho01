from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_psychologist
from app.crud.psychologists import get_psychologists
from app.db.deps import get_db
from app.models.user import User
from app.schemas.psychologists import PsychologistListOut
from app.schemas.user import PsychologistUpdate, UserRead
from app.services.avatar import image_path, replace_avatar

router = APIRouter(prefix="/psychologists", tags=["psychologists"])


@router.post(
    "/me/photo",
    response_model=UserRead,
    description="Upload or replace your public photo. Multipart field: file. JPEG, PNG or WebP; maximum 5 MiB and 16 megapixels; no animation. Stored as WebP up to 1024px without metadata.",
)
async def upload_photo(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_psychologist),
):
    return await replace_avatar(db, user, file)


@router.delete(
    "/me/photo",
    response_model=UserRead,
    description="Delete your photo. Repeated deletion is safe; avatar_url becomes null.",
)
async def delete_photo(
    db: AsyncSession = Depends(get_db), user: User = Depends(require_psychologist)
):
    return await replace_avatar(db, user, None)


@router.get(
    "/photos/{filename}",
    response_class=FileResponse,
    description="Public sanitized profile photo; only current photos of active psychologists are served.",
)
async def get_photo(filename: str, db: AsyncSession = Depends(get_db)):
    path = image_path(filename)
    owner = await db.scalar(
        select(User.id).where(
            User.avatar_filename == filename,
            User.is_active.is_(True),
            User.is_psychologist.is_(True),
        )
    )
    if owner is None or not path.is_file():
        raise HTTPException(404, "Photo not found")
    return FileResponse(
        path,
        media_type="image/webp",
        headers={"Cache-Control": "no-cache", "X-Content-Type-Options": "nosniff"},
    )


@router.get(
    "",
    response_model=list[PsychologistListOut],
)
async def get_psychologists_endpoint(
    db: AsyncSession = Depends(get_db),
):
    return await get_psychologists(db)


@router.get("/me", response_model=UserRead)
async def get_my_psychologist_profile(
    user: User = Depends(require_psychologist),
):
    return user


@router.patch("/me", response_model=UserRead)
async def update_my_psychologist_profile(
    data: PsychologistUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_psychologist),
):
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(user, field, value)

    db.add(user)
    await db.commit()
    await db.refresh(user)

    return user
