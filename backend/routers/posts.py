# backend/routers/posts.py

from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload 
from typing import List

import schemas, models
from database import get_db
from auth_utils import get_current_active_user

router = APIRouter(
    prefix="/posts",
    tags=["Posts"]
)

# --- 1. GET FEED ---
@router.get("/", response_model=List[schemas.Post])
async def get_feed(
    skip: int = 0, 
    limit: int = 20, 
    db: AsyncSession = Depends(get_db)
):
    query = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),       
            selectinload(models.Post.likes),        
            selectinload(models.Post.comments).selectinload(models.Comment.author), 
            selectinload(models.Post.resolved_by)   
        )
        .where(models.Post.status != models.TaskStatus.COMPLETED)
        .order_by(desc(models.Post.created_at))
        .offset(skip)
        .limit(limit)
    )
    result = await db.execute(query)
    return result.scalars().all()

# --- 2. CREATE REQUEST (FIXED) ---
@router.post("/", response_model=schemas.Post, status_code=status.HTTP_201_CREATED)
async def create_request(
    post_data: schemas.PostCreate,
    db: AsyncSession = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    # 1. Create and Save
    new_post = models.Post(
        image_url=post_data.image_url,
        image_public_id=post_data.image_public_id,
        caption=post_data.caption,
        latitude=post_data.latitude,
        longitude=post_data.longitude,
        author_id=current_user.id,
        status=models.TaskStatus.OPEN
    )
    db.add(new_post)
    await db.commit()
    await db.refresh(new_post)
    
    # 2. CRITICAL FIX: Re-fetch the post with eager loading.
    # This ensures 'comments', 'likes', 'author' are populated and ready for Pydantic.
    # Trying to set new_post.comments = [] manually causes crashes in Async mode.
    query = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),
            selectinload(models.Post.likes),
            selectinload(models.Post.comments),
            selectinload(models.Post.resolved_by)
        )
        .where(models.Post.id == new_post.id)
    )
    result = await db.execute(query)
    loaded_post = result.scalars().first()
    
    return loaded_post

# --- 3. SUBMIT PROOF ---
@router.post("/{post_id}/submit-proof")
async def submit_proof(
    post_id: int,
    proof_image_url: str, 
    db: AsyncSession = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    result = await db.execute(select(models.Post).where(models.Post.id == post_id))
    post = result.scalars().first()

    if not post:
        raise HTTPException(status_code=404, detail="Task not found")

    if post.status != models.TaskStatus.OPEN:
        raise HTTPException(status_code=400, detail="Task is not open for contributions")
    
    if post.author_id == current_user.id:
         raise HTTPException(status_code=400, detail="You cannot claim your own task")

    post.status = models.TaskStatus.PENDING_VERIFICATION
    post.resolved_by_id = current_user.id
    post.proof_image_url = proof_image_url
    
    await db.commit()
    return {"message": "Proof submitted! Waiting for author approval."}

# --- 4. APPROVE & CLOSE ---
@router.post("/{post_id}/approve")
async def approve_and_close(
    post_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    query = (
        select(models.Post)
        .options(selectinload(models.Post.resolved_by)) 
        .where(models.Post.id == post_id)
    )
    result = await db.execute(query)
    post = result.scalars().first()

    if not post:
        raise HTTPException(status_code=404, detail="Task not found")

    if post.author_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the author can approve this")

    if post.status != models.TaskStatus.PENDING_VERIFICATION:
        raise HTTPException(status_code=400, detail="No pending proof to approve")

    if post.resolved_by:
        post.resolved_by.points += 50
    
    post.status = models.TaskStatus.COMPLETED
    
    await db.commit()
    return {"message": "Task approved! Points awarded."}