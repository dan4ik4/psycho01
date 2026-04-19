from fastapi import FastAPI, Request
from starlette.middleware.base import BaseHTTPMiddleware
import logging

from app.routes import api
from app.jobs.scheduler import start_scheduler, stop_scheduler

app = FastAPI(
    title="TheraAI",
    version="0.1.0",
    docs_url="/docs",
    openapi_url="/openapi.json",
    debug=True,
)

# единая точка подключения всех маршрутов
app.include_router(api)

# ——— мидлварь для логов исключений ———
logger = logging.getLogger("uvicorn.error")

async def _log_exceptions(request: Request, call_next):
    try:
        return await call_next(request)
    except Exception as e:
        logger.exception("UNHANDLED: %s", e)
        raise

app.add_middleware(BaseHTTPMiddleware, dispatch=_log_exceptions)

@app.on_event("startup")
async def startup_event():
    start_scheduler()


@app.on_event("shutdown")
async def shutdown_event():
    stop_scheduler()