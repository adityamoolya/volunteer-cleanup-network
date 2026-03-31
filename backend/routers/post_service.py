"""
    File: backend/routers/post_service.py
    Description: 
        Implements core business logic for processing cleanup posts.
"""

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload
from datetime import datetime
from zoneinfo import ZoneInfo
import models, schemas

#helper to load all relationships (prevents repetition)
def post_loader():
    return (
        select(models.Post)
        .options(
            selectinload(models.Post.author),       
            selectinload(models.Post.likes),        
            selectinload(models.Post.comments).selectinload(models.Comment.author), 
            selectinload(models.Post.resolved_by),
            selectinload(models.Post.volunteer)
        )
    )

async def get_feed(db: AsyncSession, skip: int = 0, limit: int = 20):
    query = (
        post_loader()
        .where(models.Post.status != models.TaskStatus.COMPLETED)
        .order_by(desc(models.Post.created_at))
        .offset(skip)
        .limit(limit)
    )
    result = await db.execute(query)
    return result.scalars().all()

async def start_work(db: AsyncSession, post_id: str, volunteer_id: str, start_image_url: str):
    # 1. Fetch
    result = await db.execute(select(models.Post).where(models.Post.id == post_id))
    post = result.scalars().first()
    
    # 2. Validate (Return False or raise generic errors if validation fails)
    if not post or post.status != models.TaskStatus.OPEN:
        return None 

    # 3. Update State
    post.status = models.TaskStatus.IN_PROGRESS
    post.volunteer_id = volunteer_id
    post.start_image_url = start_image_url
    post.volunteer_start_timestamp = datetime.now(ZoneInfo("Asia/Kolkata"))
    
    await db.commit()
    
    # 4. Return fresh object
    result = await db.execute(post_loader().where(models.Post.id == post_id))
    return result.scalars().first()