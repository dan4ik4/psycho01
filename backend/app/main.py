from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.errors import AppError
from app.core.settings import settings
from app.routes import api
from app.ai.routes import api as ai_api
from app.jobs.scheduler import start_scheduler, stop_scheduler


logger = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(app: FastAPI):
    start_scheduler()
    try:
        yield
    finally:
        stop_scheduler()


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
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "detail": str(exc),
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