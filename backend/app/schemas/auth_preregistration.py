from pydantic import BaseModel, EmailStr, Field


class PreRegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class ConfirmIn(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6, pattern=r"^\d{6}$")