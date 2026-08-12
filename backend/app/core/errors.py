class AppError(Exception):
    status_code = 400


class ValidationError(AppError):
    status_code = 400


class ForbiddenError(AppError):
    status_code = 403


class NotFoundError(AppError):
    status_code = 404


class ConflictError(AppError):
    status_code = 409

class InternalError(AppError):
    status_code = 500