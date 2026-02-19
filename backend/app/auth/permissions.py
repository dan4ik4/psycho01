from collections.abc import Iterable

from fastapi import Depends, HTTPException, status

from app.auth.deps import current_active_user
from app.models.user import User, UserRole


def require_roles(*roles: UserRole):
    allowed = set(roles)

    def _dep(user: User = Depends(current_active_user)) -> User:
        if user.role not in allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not enough permissions",
            )
        return user

    return _dep


# Готовые зависимости (чтобы в роутерах было супер читаемо)
require_owner = require_roles(UserRole.owner)
require_psychologist = require_roles(UserRole.psychologist)
require_owner_or_psychologist = require_roles(UserRole.owner, UserRole.psychologist)