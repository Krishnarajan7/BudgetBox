from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.schemas import (
    RegisterRequest,
    LoginRequest,
    TokenResponse,
    RefreshRequest,
)
from app.auth.service import register_user, authenticate_user
from app.auth.service_tokens import (
    refresh_access_token,
    logout,
    logout_all_sessions,
)
from app.auth.deps import get_current_user
from app.models.user import User
from app.core.database import get_db

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(
    data: RegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    try:
        user = await register_user(db, data.email, data.password)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    return {"id": user.id, "email": user.email}


@router.post("/login", response_model=TokenResponse)
async def login(
    data: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    result = await authenticate_user(db, data.email, data.password)

    if not result:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token, refresh_token = result
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
    }


@router.post("/refresh", response_model=TokenResponse)
async def refresh(
    data: RefreshRequest,
    db: AsyncSession = Depends(get_db),
):
    access_token = await refresh_access_token(db, data.refresh_token)

    if not access_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return {
        "access_token": access_token,
        "refresh_token": data.refresh_token,
    }


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout_user(
    data: RefreshRequest,
    db: AsyncSession = Depends(get_db),
):
    await logout(db, data.refresh_token)


@router.post("/logout-all", status_code=status.HTTP_204_NO_CONTENT)
async def logout_all(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await logout_all_sessions(db, user.id)
    

