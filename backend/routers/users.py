'''
    File: backend/routers/users.py
    Description: 
        Handles API endpoints related to user profiles, dashboard statistics, 
        and leaderboards. This router manages how user data is retrieved and 
        displayed across the application.

    Key Endpoints:
        - GET /me: Retrieves the fully detailed, private profile of the currently 
        authenticated user (requires authentication).
        - GET /profile/stats: Aggregates dashboard data including total tasks created, 
        tasks solved, and total points. Returns the user's active requests and 
        contributions (requires authentication).
        - GET /leaderboard: Fetches the top 10 public user profiles ranked by points 
        for the global leaderboard.

    Security & Privacy Notes:
        - Enforces data privacy by converting internal database models to the 
        `schemas.UserPublic` schema before returning data to the client, ensuring 
        emails, passwords, and other sensitive details are never exposed on public 
        feeds or leaderboards.
        - Routes interacting with a specific user's private data require active 
        authentication via the `get_current_user` dependency.
'''
import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, func, or_
from sqlalchemy.orm import selectinload
from typing import List

import schemas
from auth.models import User
from database import get_db
from auth.dependencies import get_current_user
import models

router = APIRouter(
    prefix="/users",
    tags=["Users"]
)

# --- 1. PRIVATE PROFILE (Settings Page) ---
# Returns email and full details. Only for the user themselves.
@router.get("/me", response_model=schemas.User)
async def read_users_me(current_user: User = Depends(get_current_user)):
    return current_user

# --- 2. DASHBOARD (Home Screen) ---
# Returns only safe public info + game stats.
@router.get("/profile/stats")
async def get_my_stats(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # 1. Tasks I created
    created_q = select(func.count()).where(models.Post.author_id == current_user.id)
    created_res = await db.execute(created_q)
    created_count = created_res.scalar()

    # 2. Tasks I solved (Completed contributions)
    solved_q = select(func.count()).where(models.Post.resolved_by_id == current_user.id)
    solved_res = await db.execute(solved_q)
    solved_count = solved_res.scalar()

    # 3. Get my requests (posts I created)
    my_requests_q = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),
            selectinload(models.Post.volunteer),
            selectinload(models.Post.resolved_by)
        )
        .where(models.Post.author_id == current_user.id)
        .order_by(desc(models.Post.created_at))
    )
    
    # 4. Get my contributions - includes:
    #    - Posts where I am the active volunteer (volunteer_id)
    #    - Posts where I completed the work (resolved_by_id)
    my_contribs_q = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),
            selectinload(models.Post.volunteer),
            selectinload(models.Post.resolved_by)
        )
        .where(
            or_(
                models.Post.volunteer_id == current_user.id,
                models.Post.resolved_by_id == current_user.id
            )
        )
        .order_by(desc(models.Post.created_at))
    )
    
    my_requests = (await db.execute(my_requests_q)).scalars().all()
    my_contribs = (await db.execute(my_contribs_q)).scalars().all()

    my_rewards_q = (
        select(models.RedemptionRequest)
        .options(selectinload(models.RedemptionRequest.reward))
        .where(models.RedemptionRequest.user_id == current_user.id)
        .order_by(desc(models.RedemptionRequest.created_at))
    )
    my_rewards = (await db.execute(my_rewards_q)).scalars().all()

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
        "my_contributions": my_contribs,
        "my_rewards": my_rewards
    }

# --- 3. LEADERBOARD ---
@router.get("/leaderboard", response_model=List[schemas.UserPublic])
async def get_leaderboard(db: AsyncSession = Depends(get_db)):
    # Fetch top 10 users by points
    query = select(User).order_by(desc(User.points)).limit(10)
    result = await db.execute(query)
    return result.scalars().all()


@router.delete("/delete/{user_id}")
async def delete_user(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    from fastapi import HTTPException
    from auth.models import Admin
    
    # Check if the current user is deleting their own account 
    if str(current_user.id) != str(user_id):
        
        raise HTTPException(status_code=403, detail="Not authorized to delete other users")

    # Find the user to delete
    user_to_delete = await db.get(User, str(user_id))
    if not user_to_delete:
        raise HTTPException(status_code=404, detail="User not found")

    # Delete the user
    await db.delete(user_to_delete)
    await db.commit()

    return {"message": "User deleted successfully"}


# --- 5. TEST NOTIFICATIONS ---

from pydantic import BaseModel
from typing import Optional

class TestNotificationRequest(BaseModel):
    device_token: str
    title: Optional[str] = "🧪 Test Notification"
    body: Optional[str] = "If you see this, notifications work!"


# 5a. RAW TEST — just paste any FCM token, no login needed
@router.post("/ping-device", tags=["Debug"])
async def ping_device(payload: TestNotificationRequest):
    """
    Send a notification to ANY device by its FCM token.
    
    How to use:
    1. Open the Flutter app → login → check console logs for "📱 FCM Token: ..."
    2. Copy that token
    3. Paste it here and hit Execute
    4. Your phone should buzz 🎉
    """
    from fastapi import HTTPException
    from routers.notification_service import send_notification

    result = send_notification(
        token=payload.device_token,
        title=payload.title,
        body=payload.body,
        data={"type": "test"}
    )

    if isinstance(result, dict) and result.get("error") == "unregistered":
        raise HTTPException(status_code=410, detail="Token is invalid/expired. Get a fresh one by re-logging in the app.")
    
    if not isinstance(result, dict) or not result.get("ok"):
        error_detail = result.get("error", "Unknown error") if isinstance(result, dict) else str(result)
        raise HTTPException(status_code=500, detail=f"Firebase failed: {error_detail}")

    return {
        "message": "✅ Notification sent!",
        "firebase_response": result.get("firebase_response"),
        "token_preview": payload.device_token[:25] + "..."
    }


# 5b. AUTH TEST — sends to the currently logged-in user's stored token
@router.post("/test-notification")
async def test_notification(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    from fastapi import HTTPException
    from routers.notification_service import send_notification

    token = getattr(current_user, "fcm_token", None)
    
    if not token:
        raise HTTPException(
            status_code=400, 
            detail=f"No FCM token stored for user '{current_user.username}'. "
                   f"Make sure you logged in from the mobile app (not web/Swagger)."
        )

    result = send_notification(
        token=token,
        title="🧪 Test Notification",
        body=f"Hey @{current_user.username}, notifications are working!",
        data={"type": "test"}
    )

    if isinstance(result, dict) and result.get("error") == "unregistered":
        current_user.fcm_token = None
        db.add(current_user)
        await db.commit()
        raise HTTPException(
            status_code=410,
            detail="FCM token is stale/expired. Please re-login from the app to get a fresh token."
        )
    
    if not isinstance(result, dict) or not result.get("ok"):
        error_detail = result.get("error", "Unknown error") if isinstance(result, dict) else str(result)
        raise HTTPException(status_code=500, detail=f"Firebase failed: {error_detail}")

    return {
        "message": "✅ Test notification sent!",
        "firebase_response": result.get("firebase_response"),
        "fcm_token_prefix": token[:20] + "...",
        "username": current_user.username
    }