from pydantic import EmailStr, BaseModel
from fastapi_users import schemas
import uuid
from typing import Optional
from app.models.user import UserRole

class UserRead(schemas.BaseUser[uuid.UUID]):
    role: UserRole

class UserCreate(schemas.BaseUserCreate):
    email: EmailStr
    password: str
    role: UserRole = UserRole.user

class UserUpdateSelf(BaseModel):
    password: Optional[str] = None
    # username: Optional[str] = None       # если добавим
    # avatar_url: Optional[str] = None     # если понадобится

class UserAdminUpdate(BaseModel):
    email: Optional[EmailStr] = None
    role: Optional[UserRole] = None
    is_active: Optional[bool] = None
