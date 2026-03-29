from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timedelta
from database import get_db
from auth.models import User, RefreshToken, OAuthAccount
from auth.schemas import FirebaseAuthRequest, TokenResponse
from auth.utils.oauth_verify import verify_supabase_token
from auth.utils.jwt import (
    create_access_token, create_refresh_token,
    hash_refresh_token, REFRESH_TOKEN_EXPIRE_DAYS
)

router = APIRouter()


@router.post("/github", response_model=TokenResponse)
async def github_oauth(payload: FirebaseAuthRequest, db: AsyncSession = Depends(get_db)):

    token_data = verify_supabase_token(payload.firebase_token)
    if not token_data:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    email            = token_data["email"]
    provider_user_id = token_data["provider_user_id"]
    provider         = token_data["provider"]

    result = await db.execute(
        select(OAuthAccount).where(
            OAuthAccount.provider == provider,
            OAuthAccount.provider_user_id == provider_user_id
        )
    )
    oauth_account = result.scalar_one_or_none()

    if oauth_account:
        result = await db.execute(select(User).where(User.id == oauth_account.user_id))
        user = result.scalar_one_or_none()
    else:
        result = await db.execute(select(User).where(User.email == email))
        user = result.scalar_one_or_none()

        if not user:
            user = User(email=email)
            db.add(user)
            await db.flush()

        db.add(OAuthAccount(
            user_id          = user.id,
            provider         = provider,
            provider_user_id = provider_user_id,
            email            = email
        ))

    if user.is_banned:
        raise HTTPException(status_code=403, detail="User is banned")

    access_token  = create_access_token(user.id)
    refresh_token = create_refresh_token()

    db.add(RefreshToken(
        user_id     = user.id,
        token_hash  = hash_refresh_token(refresh_token),
        device_info = payload.device_info,
        expires_at  = datetime.utcnow() + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    ))
    await db.commit()

    return TokenResponse(access_token=access_token, refresh_token=refresh_token)