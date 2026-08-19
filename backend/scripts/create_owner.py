import asyncio
import getpass

from sqlalchemy import func, select

from app.db.session import AsyncSessionLocal
from app.models.user import User
from app.auth.deps import UserManager
from fastapi_users_db_sqlalchemy import SQLAlchemyUserDatabase
from app.core.email import normalize_email


async def create_superuser() -> None:
    email = normalize_email(input("Admin email: "))
    password = getpass.getpass("Admin password: ")

    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(User).where(
                func.lower(User.email) == email
            )
        )
        existing_user = result.scalar_one_or_none()

        if existing_user:
            print("User with this email already exists")
            return

        user_db = SQLAlchemyUserDatabase(session, User)
        user_manager = UserManager(user_db)

        hashed_password = user_manager.password_helper.hash(password)

        admin = User(
            email=email,
            hashed_password=hashed_password,
            is_active=True,
            is_verified=True,
            is_superuser=True,
            is_psychologist=False,
        )

        session.add(admin)
        await session.commit()

        print(f"Superuser created: {email}")


if __name__ == "__main__":
    asyncio.run(create_superuser())