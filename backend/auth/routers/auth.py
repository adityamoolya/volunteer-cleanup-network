"""
    File: backend/auth/routers/auth.py
    Description: 
        Contains the main authentication endpoints for login, signup, and token refresh.
"""

'''
Before   →  every refresh hit Postgres to validate token
After    →  refresh checks Redis first (microseconds)
             Postgres only used for user lookup + audit log
             logout is instant Redis key deleted immediately
'''
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timedelta
from database import get_db
from auth.models import User, RefreshToken
from auth.schemas import (
    RegisterRequest, LoginRequest, RefreshRequest,
    LogoutRequest, TokenResponse, UserResponse, MessageResponse
)
from auth.utils.hashing import hash_password, verify_password
from auth.utils.jwt import (
    create_access_token, create_refresh_token,
    hash_refresh_token, REFRESH_TOKEN_EXPIRE_DAYS
)
from auth.dependencies import get_current_user

from auth.redis_client import redis
from auth.utils.jwt import REFRESH_TOKEN_EXPIRE_DAYS

router = APIRouter()


@router.post("/register", response_model=MessageResponse, status_code=201)
async def register(payload: RegisterRequest, db: AsyncSession = Depends(get_db)):

    result = await db.execute(select(User).where(User.email == payload.email))
    existing = result.scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    result = await db.execute(select(User).where(User.username == payload.username))
    existing = result.scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=400, detail="Username already taken")

    user = User(email=payload.email, username=payload.username, password_hash=hash_password(payload.password))
    db.add(user)
    await db.commit()
    await db.refresh(user)

    return {"message": "User registered successfully"}


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):

    result = await db.execute(select(User).where(User.email == payload.email))
    user = result.scalar_one_or_none()

    if not user or not user.password_hash:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if user.is_banned:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    access_token  = create_access_token(user.id)
    refresh_token = create_refresh_token()
    token_hash    = hash_refresh_token(refresh_token)

    db.add(RefreshToken(
        user_id    = user.id,
        token_hash = token_hash,
        expires_at = datetime.utcnow() + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    ))
    await db.commit()

    # store in Redis with TTL
    redis.setex(
        f"refresh:{token_hash}",
        REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60,   # TTL in seconds
        user.id
    )

    return TokenResponse(access_token=access_token, refresh_token=refresh_token)

@router.post("/refresh", response_model=TokenResponse)
async def refresh(payload: RefreshRequest, db: AsyncSession = Depends(get_db)):

    token_hash = hash_refresh_token(payload.refresh_token)

    # check Redis first — fast path
    user_id = redis.get(f"refresh:{token_hash}")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user or user.is_banned:
        raise HTTPException(status_code=403, detail="Access denied")

    # rotate — delete old from Redis + DB
    redis.delete(f"refresh:{token_hash}")

    result2 = await db.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.is_revoked == False
        )
    )
    db_token = result2.scalar_one_or_none()
    if db_token:
        db_token.is_revoked = True

    new_access_token  = create_access_token(user.id)
    new_refresh_token = create_refresh_token()
    new_token_hash    = hash_refresh_token(new_refresh_token)

    db.add(RefreshToken(
        user_id    = user.id,
        token_hash = new_token_hash,
        expires_at = datetime.utcnow() + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    ))
    await db.commit()

    # store new token in Redis
    redis.setex(
        f"refresh:{new_token_hash}",
        REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60,
        user.id
    )

    return TokenResponse(access_token=new_access_token, refresh_token=new_refresh_token)

@router.post("/logout", response_model=MessageResponse)
async def logout(payload: LogoutRequest, db: AsyncSession = Depends(get_db)):

    token_hash = hash_refresh_token(payload.refresh_token)

    # delete from Redis instantly
    redis.delete(f"refresh:{token_hash}")

    # mark revoked in DB for audit log
    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.is_revoked == False
        )
    )
    db_token = result.scalar_one_or_none()
    if db_token:
        db_token.is_revoked = True
        await db.commit()

    return {"message": "Logged out successfully"}


@router.get("/me", response_model=UserResponse)
async def me(current_user: User = Depends(get_current_user)):
    return current_user