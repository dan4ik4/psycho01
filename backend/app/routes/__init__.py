from fastapi import APIRouter

from app.auth.deps import auth_backend, fastapi_users
from app.routes.health import router as health_router
from app.routes.profile import router as profile_router
from app.routes.psychologist_profile import router as psychologist_profile_router
from app.routes.users_admin import router as users_admin_router
from app.routes.users_me import router as users_me_router
from app.schemas.user import UserCreate, UserRead
from app.routes.auth_preregistration import router as auth_preregister_router
from app.routes.change_password import router as auth_password_router
from app.routes.psychologists import router as psychologists_router
from app.routes.patient_assignment import router as patient_assignment_router
from app.routes.psychologist_slots import router as psychologist_slots_router
from app.routes.appointments import router as appointments_router
from app.routes.appointments_agora import router as appointments_agora_router

api = APIRouter(prefix="/api/v1")

# health
api.include_router(health_router)

#slots
api.include_router(psychologist_slots_router)

#slots(patient)
api.include_router(appointments_router)

#agora
api.include_router(appointments_agora_router)

#preregister
api.include_router(auth_preregister_router)

#relation patient-psychologist
api.include_router(patient_assignment_router)

#list of psychologists
api.include_router(psychologists_router)

# profile
api.include_router(profile_router)
api.include_router(psychologist_profile_router)

#password
api.include_router(auth_password_router, tags=["auth"])

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
# api.include_router(
#     fastapi_users.get_register_router(UserRead, UserCreate),
#     prefix="/auth",
#     tags=["auth"],
# )

# users
api.include_router(users_me_router)
api.include_router(users_admin_router)