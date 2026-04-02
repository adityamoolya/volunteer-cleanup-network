'''
    File: backend/routers/admins.py
    Description:
        Admin-only endpoints. Every route in this router is protected by the
        `get_current_admin` dependency, which verifies the caller has an entry
        in the Admin table before any business logic runs.

    Key Endpoints:
        - DELETE /admin/remove/{user_id}  — Hard-delete any user account.
        - POST   /admin/promote/{user_id} — Promote a regular user to admin.
        - POST   /admin/rewards/requests/{request_id}/review - Approve/reject redemption requests.

    Security Note:
        The `get_current_admin` dependency is injected at the router level via
        `dependencies=[...]`, so it is impossible to forget the check on a new
        route — FastAPI enforces it automatically.
'''

#TODO: implement an autoemail clienta
from typing import Optional ,List

from fastapi import APIRouter, Depends, HTTPException
from schemas import BanRequest, UserAdminView
import schemas
from models import Reward, RedemptionRequest, RedemptionStatus
from routers.notification_service import notify_user_async
from sqlalchemy.ext.asyncio import AsyncSession # type: ignore
import uuid
from sqlalchemy import select # type: ignore

from auth.models import User, Admin
from auth.dependencies import get_db, get_current_user

# reusable admin guard

async def get_current_admin(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> User:
    """
    Dependency that succeeds only when the authenticated user has a row in the
    Admin table. Inject this wherever admin privilege is required.
    """
    admin_entry = await db.get(Admin, current_user.id)
    if not admin_entry:
        raise HTTPException(status_code=403, detail="Admin privileges required")
    return current_user          # pass the user object through for convenience


# every route auto-requires admin 

router = APIRouter(
    prefix="/admin",
    tags=["Admin panel"],
    # dependencies=[Depends(get_current_admin)]
)


#forcefullt remoce a user from app's database
@router.delete("/remove/{user_id}")
async def remove_user(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
):
    """Hard-delete any user account. Admin only."""
    user_to_delete = await db.get(User, str(user_id))
    if not user_to_delete:
        raise HTTPException(status_code=404, detail="User not found")

    await db.delete(user_to_delete)
    await db.commit()
    return {"message": f"User {user_id} deleted successfully"}


#promotes a user to admin  by an admin
@router.post("/promote/{user_id}")
async def promote_user(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
):
    """Promote a regular user to admin. Admin only."""
    target_user = await db.get(User, str(user_id))
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    existing = await db.get(Admin, str(user_id))
    if existing:
        return {"message": "already an admin"}

    new_admin = Admin(
        id=str(user_id),
        username=target_user.username,   #pulled from User at promotion time
    )
    db.add(new_admin)
    await db.commit()

    return {"message": "promoted to admin successfully"}




#banning a user , power given to admin 
@router.post("/ban/{user_id}")
async def ban_user(
    user_id: uuid.UUID,
    payload: BanRequest,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """
    Flips is_banned on the User row.
      ban: true  → bans the user
      ban: false → unbans the user
    """
    target = await db.get(User, str(user_id))
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    # Prevent admins from banning other admins
    target_admin_entry = await db.get(Admin, str(user_id))
    if target_admin_entry:
        raise HTTPException(status_code=403, detail="Cannot ban another admin")

    if payload.ban and target.is_banned:
        return {"message": f"{target.username} is already banned"}

    if not payload.ban and not target.is_banned:
        return {"message": f"{target.username} is not banned"}

    target.is_banned = payload.ban
    await db.commit()

    action = "banned" if payload.ban else "unbanned"
    return {"message": f"{target.username} has been {action}"}


#admin search panel 
@router.get("/users/search")
async def search_user(
    username: Optional[str] = None,
    email: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    """Look up a user's UUID by username or email. At least one must be provided."""
    if not username and not email:
        raise HTTPException(status_code=400, detail="Provide at least a username or email")

    query = select(User)

    if username and email:
        query = query.where((User.username == username) | (User.email == email))
    elif username:
        query = query.where(User.username == username)
    else:
        query = query.where(User.email == email)

    result = await db.execute(query)
    target = result.scalar_one_or_none()

    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    return {
        "id": target.id,
        "username": target.username,
        "email": target.email,
        "is_banned": target.is_banned
    }

# reward approval by admin

@router.post("/rewards", response_model=schemas.Reward)
async def create_reward(
    reward_in: schemas.RewardCreate,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin)
):
    """Admin only: Add a new reward to the catalog."""
    new_reward = Reward(**reward_in.model_dump())
    db.add(new_reward)
    await db.commit()
    await db.refresh(new_reward)
    return new_reward

@router.get("/rewards/requests", response_model=List[schemas.RedemptionRequestItem])
async def get_pending_requests(
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin)
):
    """Admin only: View all pending redemption requests."""
    query = select(RedemptionRequest).where(RedemptionRequest.status == RedemptionStatus.PENDING)
    result = await db.execute(query)
    return result.scalars().all()

@router.post("/rewards/requests/{request_id}/review")
async def review_request(
    request_id: str,
    payload: schemas.RewardReviewRequest,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin)
):
    """
    Admin only: Approve or reject a redemption request.
      approve: true  → approves and notifies user
      approve: false → rejects, refunds points, restores stock, notifies user
    """
    req = await db.get(RedemptionRequest, request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")
    if req.status != RedemptionStatus.PENDING:
        raise HTTPException(status_code=400, detail="Request is not pending")

    if payload.approve:
        req.status = RedemptionStatus.APPROVED
    else:
        req.status = RedemptionStatus.REJECTED

        # Refund user and restore stock
        target_user = await db.get(User, req.user_id)
        reward = await db.get(Reward, req.reward_id)
        if target_user and reward:
            target_user.points += reward.cost_in_points
            reward.stock += 1

    await db.commit()

    # Notify the user
    target_user = await db.get(User, req.user_id)
    if target_user:
        if payload.approve:
            title = "Reward Approved!"
            body = "Congrats, your coupon is ready and is sent to your email"
        else:
            title = "Reward Rejected"
            body = "Your reward request was rejected. Your points have been refunded."

        await notify_user_async(db, target_user, title, body)
#TODO: implement an autoemail client
    action = "approved" if payload.approve else "rejected and points refunded"
    return {"message": f"Request {action}"}


