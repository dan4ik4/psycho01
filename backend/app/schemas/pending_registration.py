from typing import Annotated
from pydantic import BaseModel, EmailStr, StringConstraints


PasswordStr = Annotated[str, StringConstraints(min_length=8, max_length=128)]
OTPCodeStr = Annotated[str, StringConstraints(min_length=6, max_length=6, pattern=r"^\d{6}$")]


class PendingRegistrationCreate(BaseModel):
    email: EmailStr
    password: PasswordStr


class PendingRegistrationConfirm(BaseModel):
    email: EmailStr
    otp_code: OTPCodeStr


class PendingRegistrationResend(BaseModel):
    email: EmailStr