"""Decode, strip metadata and store bounded public profile pictures."""

import io
import logging
import re
import uuid
import warnings
from pathlib import Path

from app.core.settings import settings
from app.models.user import User
from fastapi import HTTPException, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import select
from starlette.concurrency import run_in_threadpool

MAX_BYTES = 5 * 1024 * 1024
MAX_PIXELS = 16_000_000
FORMATS = {"image/jpeg": "JPEG", "image/png": "PNG", "image/webp": "WEBP"}
logger = logging.getLogger("uvicorn.error")


def image_path(filename):
    if not re.fullmatch(r"[0-9a-f]{32}\.webp", filename):
        raise HTTPException(404, "Photo not found")
    return Path(settings.AVATAR_STORAGE_DIR) / filename


def normalize_image(data, content_type):
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as image:
                if (
                    image.format != FORMATS[content_type]
                    or image.width * image.height > MAX_PIXELS
                ):
                    raise ValueError("Invalid image format or dimensions")
                if getattr(image, "n_frames", 1) != 1:
                    raise ValueError("Animated photos are not supported")
                image.load()
                image = ImageOps.exif_transpose(image)
                image.thumbnail((1024, 1024))
                # New image drops EXIF, GPS, text and other source metadata.
                converted = image.convert("RGB")
                clean = Image.new("RGB", converted.size)
                clean.paste(converted)
                output = io.BytesIO()
                clean.save(output, format="WEBP", quality=85)
                return output.getvalue()
    except (
        UnidentifiedImageError,
        OSError,
        ValueError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
    ):
        raise HTTPException(
            422, "Invalid image; use a still JPEG, PNG or WebP up to 16 megapixels"
        ) from None


def remove_file(filename):
    if filename:
        try:
            image_path(filename).unlink(missing_ok=True)
        except OSError:
            logger.warning("Could not remove obsolete profile image %s", filename)


async def replace_avatar(db, user, upload: UploadFile | None):
    image_bytes = None
    if upload is not None:
        try:
            if upload.content_type not in FORMATS:
                raise HTTPException(415, "Use image/jpeg, image/png or image/webp")
            data = await upload.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                raise HTTPException(413, "Photo must not exceed 5 MiB")
            image_bytes = await run_in_threadpool(
                normalize_image, data, upload.content_type
            )
        finally:
            await upload.close()
    # Serializes replacement/deletion and avoids deleting another upload's file.
    locked = (
        await db.execute(
            select(User)
            .where(User.id == user.id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )
    ).scalar_one()
    if not locked.is_psychologist or not locked.is_active:
        raise HTTPException(403, "Only active psychologists can update a photo")
    old = locked.avatar_filename
    filename = uuid.uuid4().hex + ".webp" if image_bytes is not None else None
    try:
        if filename:
            path = image_path(filename)
            await run_in_threadpool(path.parent.mkdir, parents=True, exist_ok=True)
            await run_in_threadpool(path.write_bytes, image_bytes)
        locked.avatar_filename = filename
        await db.commit()
    except Exception:
        await db.rollback()
        await run_in_threadpool(remove_file, filename)
        raise
    await run_in_threadpool(remove_file, old)
    await db.refresh(locked)
    return locked
