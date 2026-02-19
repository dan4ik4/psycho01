from fastapi import APIRouter

from app.auth.deps import auth_backend, fastapi_users
from app.routes.health import router as health_router
from app.routes.profile import router as profile_router
from app.routes.psychologist_profile import router as psychologist_profile_router
from app.routes.users_admin import router as users_admin_router
from app.routes.users_me import router as users_me_router
from app.schemas.user import UserCreate, UserRead
from app.routes.auth_preregistration import router as auth_preregister_router

api = APIRouter(prefix="/api/v1")

# health
api.include_router(health_router)

#preregister
api.include_router(auth_preregister_router)

# profile
api.include_router(profile_router)
api.include_router(psychologist_profile_router)

# auth (fastapi-users)
api.include_router(
    fastapi_users.get_auth_router(auth_backend),
    prefix="/auth/jwt",
    tags=["auth"],
)
# api.include_router(
#     fastapi_users.get_register_router(UserRead, UserCreate),
#     prefix="/auth",
#     tags=["auth"],
# )

# users
api.include_router(users_me_router)
api.include_router(users_admin_router)