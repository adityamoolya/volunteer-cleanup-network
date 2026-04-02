'''
    File: backend/routers/rewards.py
    Description: 
        Endpoints for managing user rewards and redemptions. Handles checking available
        rewards, and allowing users to request stock.
'''
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from database import get_db
from models import Reward, RedemptionRequest, RedemptionStatus
from auth.models import User
from auth.dependencies import get_current_user
import schemas
from .admins import get_current_admin
from .notification_service import notify_user_async

router = APIRouter(
    prefix="/rewards",
    tags=["Rewards & Redemption"]
)

@router.get("/available", response_model=List[schemas.Reward])
async def get_available_rewards(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get rewards the user can currently afford and are in stock."""
    query = select(Reward).where(
        Reward.stock > 0,
        Reward.cost_in_points <= current_user.points
    )
    result = await db.execute(query)
    return result.scalars().all()

@router.post("/{reward_id}/request", response_model=schemas.RedemptionRequestItem)
async def request_reward(
    reward_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """User requests to redeem a reward. Points are deducted immediately."""
    reward = await db.get(Reward, reward_id)
    if not reward:
        raise HTTPException(status_code=404, detail="Reward not found")
        
    if reward.stock <= 0:
        raise HTTPException(status_code=400, detail="Reward is out of stock")
        
    if current_user.points < reward.cost_in_points:
        raise HTTPException(status_code=400, detail="Not enough points")
        
    # Deduct points and decrement stock
    current_user.points -= reward.cost_in_points
    reward.stock -= 1
    
    # Create request
    redemption_req = RedemptionRequest(
        user_id=current_user.id,
        reward_id=reward.id,
        status=RedemptionStatus.PENDING
    )
    db.add(redemption_req)
    await db.commit()
    await db.refresh(redemption_req)
    
    # Reload with relationships
    query = select(RedemptionRequest).where(RedemptionRequest.id == redemption_req.id)
    result = await db.execute(query)
    return result.scalars().first()
