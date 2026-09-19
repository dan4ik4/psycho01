from app.core.errors import AppError


class BillingError(AppError):
    status_code = 409

    def __init__(self, code: str, message: str, *, status_code: int = 409, **context):
        super().__init__(message)
        self.code = code
        self.status_code = status_code
        self.context = context
