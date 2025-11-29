# backend/routers/users.py

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, func
from typing import List

import schemas, models
from database import get_db
from auth_utils import get_current_active_user

router = APIRouter(
    prefix="/users",
    tags=["Users"]
)

# --- 1. PRIVATE PROFILE (Settings Page) ---
# Returns email and full details. Only for the user themselves.
@router.get("/me", response_model=schemas.User)
async def read_users_me(current_user: models.User = Depends(get_current_active_user)):
    return current_user

# --- 2. DASHBOARD (Home Screen) ---
# Returns only safe public info + game stats.
@router.get("/profile/stats")
async def get_my_stats(
    db: AsyncSession = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    # 1. Tasks I created
    created_q = select(func.count()).where(models.Post.author_id == current_user.id)
    created_res = await db.execute(created_q)
    created_count = created_res.scalar()

    # 2. Tasks I solved (Contributions)
    solved_q = select(func.count()).where(models.Post.resolved_by_id == current_user.id)
    solved_res = await db.execute(solved_q)
    solved_count = solved_res.scalar()

    # 3. Get the actual lists
    my_requests_q = select(models.Post).where(models.Post.author_id == current_user.id).order_by(desc(models.Post.created_at))
    my_contribs_q = select(models.Post).where(models.Post.resolved_by_id == current_user.id).order_by(desc(models.Post.created_at))
    
    my_requests = (await db.execute(my_requests_q)).scalars().all()
    my_contribs = (await db.execute(my_contribs_q)).scalars().all()

    return {
        # --- FIX: FILTER SENSITIVE DATA ---
        # This converts the DB object to the 'UserPublic' schema 
        # which ONLY has 'username' and 'points'. No password. No email.
        "user": schemas.UserPublic.model_validate(current_user), 
        # ----------------------------------
        "counts": {
            "created": created_count,
            "solved": solved_count,
            "points": current_user.points
        },
        "my_requests": my_requests,
        "my_contributions": my_contribs
    }

# --- 3. LEADERBOARD ---
@router.get("/leaderboard", response_model=List[schemas.UserPublic])
async def get_leaderboard(db: AsyncSession = Depends(get_db)):
    # Fetch top 10 users by points
    query = select(models.User).order_by(desc(models.User.points)).limit(10)
    result = await db.execute(query)
    return result.scalars().all()