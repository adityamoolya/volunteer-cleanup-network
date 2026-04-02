'''
    File: backend/routers/posts.py
    Description: 
        Endpoints for creating, reading, updating, and managing cleanup posts.
        This file defines the HTTP interface for the core gamification loop.
'''

# backend/routers/posts.py

from urllib.parse import urljoin
from zoneinfo import ZoneInfo
from fastapi import APIRouter, BackgroundTasks, Body, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload 
from typing import List
import httpx
from database import get_db, AsyncSessionLocal
import schemas, models
from database import get_db
from auth.dependencies import get_current_user
from auth.models import User
import os
from datetime import datetime, timezone
import logging
from . import post_service, ml_service
from routers.notification_service import notify_user_async
logger = logging.getLogger(__name__)

CLASSIFIER_MICORSERVICE = os.getenv("CLASSIFIER_MICORSERVICE") 
ml_url = urljoin(CLASSIFIER_MICORSERVICE, "/predict_with_urls") if CLASSIFIER_MICORSERVICE else None
logger.info("ML MICROSERVICE RUNNING AT "+CLASSIFIER_MICORSERVICE)

router = APIRouter(
    prefix="/posts",
    tags=["Posts"]
)

# GET FEED for community folks 
@router.get("/", response_model=List[schemas.Post])
async def get_feed(skip: int = 0, limit: int = 20, db: AsyncSession = Depends(get_db)):
    return await post_service.get_feed(db, skip, limit)


''' just in case ML spits wrong result we give author option 
    to change it manually,  
    it calls this enpoint passing post id and new cat
'''
@router.patch("/{post_id}", response_model=schemas.Post)
async def author_update_post(
    post_id: str,
    post_update: schemas.PostUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    #fetch post
    result = await db.execute(select(models.Post).where(models.Post.id == post_id))
    post = result.scalars().first()

    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    #ownership check
    if post.author_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to edit this post")

    if post.status != models.TaskStatus.OPEN:
        raise HTTPException(status_code=400, detail="Cannot edit a task that is already in progress/completed")

    #apply updates
    if post_update.predicted_class is not None:
        post.predicted_class = post_update.predicted_class
    if post_update.points is not None:
        post.points = post_update.points
    if post_update.caption is not None:
        post.caption = post_update.caption

    await db.commit()
    
    #CRITICAL FIX: Re-fetch with relationships loaded
    query = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),
            selectinload(models.Post.likes),
            selectinload(models.Post.comments).selectinload(models.Comment.author),
            selectinload(models.Post.resolved_by),
            selectinload(models.Post.volunteer)
        )
        .where(models.Post.id == post_id)
    )
    result = await db.execute(query)
    updated_post = result.scalars().first()

    return updated_post


#NEW BACKGROUND TASK: VERIFY VOLUNTEER PHOTO , phase1
async def verify_volunteer_post_ml(post_id: str, image_url: str):
    try:
        async with httpx.AsyncClient() as client:
            # call the same ML service to check the new photo
            resp = await client.post(ml_url, json={"image_url": image_url}, timeout=30.0)
            
        if resp.status_code == 200:
            data = resp.json()
            points = int(data.get("points", 0))         
            
            async with AsyncSessionLocal() as db:
                result = await db.execute(select(models.Post).where(models.Post.id == post_id))
                post = result.scalars().first()
                if post:
                    #we save this as "verified_points" for comparison later
                    post.verified_points = points 
                    await db.commit()
                    logger.info(f"[Verification-----] Post {post_id} check: ML found {points} pts")
    except Exception as e:
        logger.error(f"[Verification-----] Error: {e}")


# START WORK (Clock In) by volunteer
@router.post("/{post_id}/start_work", response_model=schemas.Post)
async def start_cleanup_work(
    post_id: str, # UUID!
    background_tasks: BackgroundTasks,
    start_image_url: str = Body(..., embed=True),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # The router handles the HTTP specific stuff (404 errors, 403 errors)
    updated_post = await post_service.start_work(
        db, post_id, current_user.id, start_image_url
    )
    
    if not updated_post:
        raise HTTPException(status_code=400, detail="Post not found or not open")
        
    if updated_post.author:
        await notify_user_async(db, updated_post.author, "Volunteer Assigned!", "A volunteer is on their way to clean up your reported spot!")
        
    # Trigger background task from the service layer
    background_tasks.add_task(ml_service.verify_volunteer_post_ml, post_id, start_image_url)
    
    return updated_post


# SUBMIT PROOF (Clock Out) 
@router.post("/{post_id}/submit_proof", response_model=schemas.Post)
async def submit_cleanup_proof(
    post_id: str,
    end_image_url: str = Body(..., embed=True),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    result = await db.execute(select(models.Post).where(models.Post.id == post_id))
    post = result.scalars().first()
    
    # Security Checks
    if not post: 
        raise HTTPException(status_code=404, detail="Post not found")
    if post.volunteer_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized (You are not the volunteer)")
    if post.status != models.TaskStatus.IN_PROGRESS:
        raise HTTPException(status_code=400, detail="Task not in progress")

    #calculate Duration
    end_time = datetime.now(timezone.utc)
    start_time = post.volunteer_start_timestamp.replace(tzinfo=timezone.utc) if post.volunteer_start_timestamp else None
    
    duration_min = 0
    if start_time:
        diff = end_time - start_time
        duration_min = int(diff.total_seconds() / 60)
    
    #update DB (Clock Out)
    post.status = models.TaskStatus.PENDING_APPROVAL
    post.end_image_url = end_image_url
    post.volunteer_end_timestamp = end_time
    post.cleanup_duration_minutes = duration_min
    
    await db.commit()
    
    #CRITICAL FIX: Re-fetch
    query = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),
            selectinload(models.Post.likes),
            selectinload(models.Post.comments).selectinload(models.Comment.author),
            selectinload(models.Post.resolved_by),
            selectinload(models.Post.volunteer)
        )
        .where(models.Post.id == post_id)
    )
    result = await db.execute(query)
    updated_post = result.scalars().first()
    
    if updated_post and updated_post.author:
        await notify_user_async(db, updated_post.author, "Job Done!", "A volunteer has submitted proof for your post. Review and approve to release the points.")
        
    return updated_post


# APPROVE & PAY (Resolution) 
@router.post("/{post_id}/approve", response_model=schemas.Post)
async def approve_work(
    post_id: str,
    final_points: int = Body(..., embed=True),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Load volunteer immediately to update points
    query = (
        select(models.Post)
        .options(selectinload(models.Post.volunteer)) 
        .where(models.Post.id == post_id)
    )
    result = await db.execute(query)
    post = result.scalars().first()
    
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
        
    from auth.models import Admin
    is_admin = await db.get(Admin, current_user.id) is not None
    
    if post.author_id != current_user.id and not is_admin:
         raise HTTPException(status_code=403, detail="Only author or an admin can approve")
    if post.status != models.TaskStatus.PENDING_APPROVAL:
         raise HTTPException(status_code=400, detail="Task is not pending approval")
         
    post.status = models.TaskStatus.COMPLETED
    post.points = final_points 
    
    if post.volunteer:
        post.volunteer.points += final_points
    
    await db.commit()

    #CRITICAL FIX: Re-fetch
    query = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),
            selectinload(models.Post.likes),
            selectinload(models.Post.comments).selectinload(models.Comment.author),
            selectinload(models.Post.resolved_by),
            selectinload(models.Post.volunteer)
        )
        .where(models.Post.id == post_id)
    )
    result = await db.execute(query)
    updated_post = result.scalars().first()
    
    if updated_post and updated_post.volunteer:
        await notify_user_async(db, updated_post.volunteer, "Work Approved!", f"Great job! Your cleanup was approved and you earned {final_points} points.")
        
    return updated_post


@router.post("/", response_model=schemas.Post, status_code=status.HTTP_201_CREATED)
async def author_create_request(
    post_data: schemas.PostCreate,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    new_post = models.Post(
        image_url=post_data.image_url,
        image_public_id=post_data.image_public_id,
        caption=post_data.caption,
        latitude=post_data.latitude,
        longitude=post_data.longitude,
        predicted_class="Analysing", 
        points=0,
        author_id=current_user.id,
        status=models.TaskStatus.OPEN
    )
    db.add(new_post)
    await db.commit()
    await db.refresh(new_post)
    
    background_tasks.add_task(ml_service.process_post_ml, new_post.id, new_post.image_url)
    
    # FIX: Re-fetch with ALL relationships including volunteer and comment authors
    query = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),
            selectinload(models.Post.likes),
            selectinload(models.Post.comments).selectinload(models.Comment.author),
            selectinload(models.Post.resolved_by),
            selectinload(models.Post.volunteer)
        )
        .where(models.Post.id == new_post.id)
    )
    result = await db.execute(query)
    return result.scalars().first()


@router.delete("/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_post(
    post_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    result = await db.execute(select(models.Post).where(models.Post.id == post_id))
    post = result.scalars().first()
    
    if not post:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")
        
    if post.author_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to delete this post")
        
    await db.delete(post)
    await db.commit()
    
    return None

@router.post("/{post_id}/cancel", response_model=schemas.Post)
async def cancel_post(
    post_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    query = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),
            selectinload(models.Post.likes),
            selectinload(models.Post.comments).selectinload(models.Comment.author),
            selectinload(models.Post.resolved_by),
            selectinload(models.Post.volunteer)
        )
        .where(models.Post.id == post_id)
    )
    result = await db.execute(query)
    post = result.scalars().first()

    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    # Author logic: Cancel an open post entirely
    if post.author_id == current_user.id:
        if post.status != models.TaskStatus.OPEN:
            raise HTTPException(status_code=400, detail="Author can only cancel OPEN posts")
        post.status = models.TaskStatus.CANCELLED
        await db.commit()
        return post

    # Volunteer logic: Drop a claimed post
    if post.volunteer_id == current_user.id:
        if post.status != models.TaskStatus.IN_PROGRESS:
            raise HTTPException(status_code=400, detail="Volunteer can only drop IN_PROGRESS posts")
        
        post.status = models.TaskStatus.OPEN
        post.volunteer_id = None
        post.start_image_url = None
        post.volunteer_start_timestamp = None
        await db.commit()
        
        if post.author:
            await notify_user_async(db, post.author, "Volunteer Dropped", "A volunteer has cancelled their claim on your post. It is now open for others.")
            
        return post

    raise HTTPException(status_code=403, detail="Not authorized to cancel this post")

