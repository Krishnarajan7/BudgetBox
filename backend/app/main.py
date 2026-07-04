from fastapi import FastAPI, Depends
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db, engine
from app.core.exception_handlers import (
    app_error_handler,
    validation_error_handler,
    unhandled_exception_handler,
)
from app.core.errors import AppError
from app.core.logging import configure_logging, RequestLoggingMiddleware

# Routers
from app.auth.router import router as auth_router
from app.profile.router import router as profile_router
from app.expenses.router import router as expenses_router
from app.analytics.router import router as analytics_router
from app.income.router import router as income_router
from app.insights.router import router as insights_router
from app.tasks.router import router as tasks_router
from app.wallets.router import router as wallets_router
from app.categories.router import router as categories_router
from app.nutrition.router import router as nutrition_router
from app.habits.router import router as habits_router
from app.transactions.router import router as transactions_router
from app.wellness.router import mood_router, water_router, sleep_router
from app.budgets.router import router as budgets_router
from app.networth.router import router as networth_router
from app.calendar_events.router import router as calendar_router
from app.journal.router import router as journal_router
from app.vault.router import router as vault_router
from app.focus.router import router as focus_router


configure_logging()

app = FastAPI(title=settings.app_name)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8080",
        "http://127.0.0.1:8080",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request logging middleware (after CORS so CORS preflights are logged too)
app.add_middleware(RequestLoggingMiddleware)


# Health / Root
@app.get("/")
async def root():
    return {
        "app": settings.app_name,
        "status": "Running Successfully",
    }


@app.get("/health/db")
async def db_health(db: AsyncSession = Depends(get_db)):
    result = await db.execute(text("SELECT 1"))
    return {
        "database": "connected",
        "result": result.scalar(),
    }


# Routers
app.include_router(auth_router)
app.include_router(profile_router)
app.include_router(expenses_router)
app.include_router(income_router)
app.include_router(transactions_router)
app.include_router(wallets_router)
app.include_router(categories_router)
app.include_router(habits_router)
app.include_router(tasks_router)
app.include_router(analytics_router)
app.include_router(insights_router)
app.include_router(nutrition_router)
app.include_router(mood_router)
app.include_router(water_router)
app.include_router(sleep_router)
app.include_router(budgets_router)
app.include_router(networth_router)
app.include_router(calendar_router)
app.include_router(journal_router)
app.include_router(vault_router)
app.include_router(focus_router)

# Exception Handlers
app.add_exception_handler(AppError, app_error_handler)
app.add_exception_handler(RequestValidationError, validation_error_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)


# Shutdown
@app.on_event("shutdown")
async def shutdown():
    await engine.dispose()
