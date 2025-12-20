from fastapi import FastAPI, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db, engine

from app.auth.router import router as auth_router
from app.expenses.router import router as expenses_router
from app.analytics.router import router as analytics_router
from app.income.router import router as income_router
from app.insights.router import router as insights_router
from app.tasks.router import router as tasks_router


app = FastAPI(title=settings.app_name)


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


app.include_router(auth_router)
app.include_router(expenses_router)
app.include_router(analytics_router)
app.include_router(income_router)
app.include_router(insights_router)
app.include_router(tasks_router)

@app.on_event("shutdown")
async def shutdown():
    await engine.dispose()
    print("Database connection pool disposed.")