from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.core.rate_limiter import limiter

from app.core.errors import AppError
from app.core.settings import settings
from app.routes import api
from app.ai.routes import api as ai_api
from app.jobs.scheduler import start_scheduler, stop_scheduler
from app.ai.openai_client import close_openai_client


logger = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(app: FastAPI):
    start_scheduler()

    try:
        yield
    finally:
        stop_scheduler()
        await close_openai_client()


async def _log_exceptions(request: Request, call_next):
    try:
        return await call_next(request)
    except Exception as e:
        logger.exception("UNHANDLED: %s", e)
        raise


async def app_error_handler(
    request: Request,
    exc: AppError,
) -> JSONResponse:
    if exc.status_code >= 500:
        logger.error(
            "INTERNAL APP ERROR: %s",
            exc,
            exc_info=(
                type(exc),
                exc,
                exc.__traceback__,
            ),
        )

        detail = "Internal server error"
    else:
        detail = str(exc)

    return JSONResponse(
        status_code=exc.status_code,
        content={
            "detail": detail,
        },
    )


app = FastAPI(
    title="TheraAI",
    version="0.1.0",
    docs_url="/docs",
    openapi_url="/openapi.json",
    debug=settings.DEBUG,
    lifespan=lifespan,
)

app.state.limiter = limiter

app.add_exception_handler(
    RateLimitExceeded,
    _rate_limit_exceeded_handler,
)

app.add_exception_handler(
    AppError,
    app_error_handler,
)

app.include_router(api)
app.include_router(ai_api)

app.add_middleware(
    BaseHTTPMiddleware,
    dispatch=_log_exceptions,
)