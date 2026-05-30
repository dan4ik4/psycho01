from fastapi import APIRouter

from app.auth.deps import auth_backend, fastapi_users
from app.routes.health import router as health_router
from app.routes.auth_preregistration import router as auth_preregister_router
from app.routes.user import router as users_me_router
from .psychologists import router as psychologists_router
from .admin import router as admin_router
from .psychologist_rating import router as psychologist_rating_router
from .patient_assignment import router as patient_assignment_router
from .slot import router as slot_router

api = APIRouter(prefix="/api/v1")

# health
api.include_router(health_router)

#preregister
api.include_router(auth_preregister_router)

#users
api.include_router(users_me_router)

#psychologists
api.include_router(psychologists_router)

#relationship
api.include_router(patient_assignment_router)

#rating
api.include_router(psychologist_rating_router)

#slots
api.include_router(slot_router)

# auth (fastapi-users)
api.include_router(
    fastapi_users.get_auth_router(auth_backend),
    prefix="/auth/jwt",
    tags=["auth"],
)

api.include_router(
    fastapi_users.get_reset_password_router(),
    prefix="/auth",
    tags=["auth"],
)

#admin
api.include_router(admin_router)