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
from auth_utils import get_current_active_user
import os
from datetime import datetime, timezone
import logging
logger = logging.getLogger(__name__)

CLASSIFIER_MICORSERVICE = os.getenv("CLASSIFIER_MICORSERVICE") 
ml_url = urljoin(CLASSIFIER_MICORSERVICE, "/predict_with_urls")
logger.info(CLASSIFIER_MICORSERVICE)

router = APIRouter(
    prefix="/posts",
    tags=["Posts"]
)



#this runs in the background. it calls the ML service and updates the DB
async def process_post_ml(post_id: int, image_url: str):
    
    # ml_url = os.getenv("CLASSIFIER_MICORSERVICE") 
    
    try:
        #calling ML service and passing the public link thatt cloudinary gave 
        async with httpx.AsyncClient() as client:
            resp = await client.post(ml_url, json={"image_url": image_url}, timeout=30.0)
            
        if resp.status_code == 200:
            data = resp.json()
            #extract data
            logger.info("ML SERVICE RESPONSE",data) 
            pred_class = data.get("predicted_class", "Unknown") 
            #if cat is misssing , defaults to unknown , points is converted to integer
            points = int(data.get("points", 0))         
            
            #update Database
            #a FRESH session because the request session is closed
            async with AsyncSessionLocal() as db:
                result = await db.execute(select(models.Post).where(models.Post.id == post_id))
                post = result.scalars().first()
                if post:
                    post.predicted_class = pred_class
                    post.points = points
                    await db.commit()
                    logger.info(f"[Background] Post {post_id} updated: {pred_class} ({points} pts)")
        else:
            logger.warning(f" [Background-----] ML Service returned {resp.status_code}")

    except Exception as e:
        logger.error(f"[Background-----] ML Error: {e}")
    except Exception as e:
        logger.error(f"[Background------] ML Error: {e}")
        
        # FAILSAFE
        async with AsyncSessionLocal() as db:
            result = await db.execute(select(models.Post).where(models.Post.id == post_id))
            post = result.scalars().first()
            if post:
                post.predicted_class = "ERROR" # <--- Give user a hint
                post.points = 0
                await db.commit()

# CREATE REQUEST , tb accessed by author only
@router.post("/", response_model=schemas.Post, status_code=status.HTTP_201_CREATED)
async def author_create_request(
    post_data: schemas.PostCreate,
    background_tasks: BackgroundTasks, # inject backgroundtasks
    db: AsyncSession = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    #create Post with "Processing" state
    new_post = models.Post(
        image_url=post_data.image_url,
        # image_public_id=post_data.image_public_id,
        caption=post_data.caption,
        latitude=post_data.latitude,
        longitude=post_data.longitude,
        
        # default values while we wait
        predicted_class="Analysing", 
        points=0,
        
        author_id=current_user.id,
        status=models.TaskStatus.OPEN
    )
    db.add(new_post)
    await db.commit()
    await db.refresh(new_post)
    
    #trigger the background task
    background_tasks.add_task(process_post_ml, new_post.id, new_post.image_url)
    
    #returning immediately 
    #we re-fetch to ensure relationships are loaded (same as our previous code)
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
    return result.scalars().first()


# GET FEED for community folks
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

# CREATE REQUEST 
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
        predicted_class=post_data.predicted_class,  #added to handle ML micorservice result
        points=post_data.points,
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

# # --- 3. SUBMIT PROOF ---
# @router.post("/{post_id}/submit-proof")
# async def submit_proof(
#     post_id: int,
#     proof_image_url: str, 
#     db: AsyncSession = Depends(get_db),
#     current_user: models.User = Depends(get_current_active_user)
# ):
#     result = await db.execute(select(models.Post).where(models.Post.id == post_id))
#     post = result.scalars().first()

#     if not post:
#         raise HTTPException(status_code=404, detail="Task not found")

#     if post.status != models.TaskStatus.OPEN:
#         raise HTTPException(status_code=400, detail="Task is not open for contributions")
    
#     if post.author_id == current_user.id:
#          raise HTTPException(status_code=400, detail="You cannot claim your own task")

#     post.status = models.TaskStatus.PENDING_VERIFICATION
#     post.resolved_by_id = current_user.id
#     post.proof_image_url = proof_image_url
    
#     await db.commit()
#     return {"message": "Proof submitted! Waiting for author approval."}

# --- 4. APPROVE & CLOSE ---
# @router.post("/{post_id}/approve")
# async def approve_and_close(
#     post_id: int,
#     db: AsyncSession = Depends(get_db),
#     current_user: models.User = Depends(get_current_active_user)
# ):
#     query = (
#         select(models.Post)
#         .options(selectinload(models.Post.resolved_by)) 
#         .where(models.Post.id == post_id)
#     )
#     result = await db.execute(query)
#     post = result.scalars().first()

#     if not post:
#         raise HTTPException(status_code=404, detail="Task not found")

#     if post.author_id != current_user.id:
#         raise HTTPException(status_code=403, detail="Only the author can approve this")

#     if post.status != models.TaskStatus.PENDING_APPROVAL:
#         raise HTTPException(status_code=400, detail="No pending proof to approve")

#     if post.resolved_by:
#         # post.resolved_by.points += 50
#         post.resolved_by.points += post.points
    
#     post.status = models.TaskStatus.COMPLETED
    
#     await db.commit()
#     return {"message": "Task approved! Points awarded."}


''' just in case ML spits wrong result we give author option 
    to change it manually,  
    it calls this enpoint passing post id and new cat
'''
@router.patch("/{post_id}", response_model=schemas.Post)
async def author_update_post(
    post_id: int,
    post_update: schemas.PostUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
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
    # We use the same query logic as 'get_feed' or 'create_request'
    query = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),
            selectinload(models.Post.likes),
            selectinload(models.Post.comments).selectinload(models.Comment.author),
            selectinload(models.Post.resolved_by)
        )
        .where(models.Post.id == post_id)
    )
    result = await db.execute(query)
    updated_post = result.scalars().first()

    return updated_post


#NEW BACKGROUND TASK: VERIFY VOLUNTEER PHOTO , phase1
async def verify_volunteer_post_ml(post_id: int, image_url: str):
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
    post_id: int,
    background_tasks: BackgroundTasks,
    start_image_url: str = Body(..., embed=True),
    db: AsyncSession = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    # 1. Fetch & Verify
    result = await db.execute(select(models.Post).where(models.Post.id == post_id))
    post = result.scalars().first()
    
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    if post.status != models.TaskStatus.OPEN:
        raise HTTPException(status_code=400, detail="Task is not open")

    #update DB (Clock In)
    post.status = models.TaskStatus.IN_PROGRESS
    post.volunteer_id = current_user.id
    post.start_image_url = start_image_url
    post.volunteer_start_timestamp = datetime.now(ZoneInfo("Asia/Kolkata")) #can use a random timezone here,i used ist
    
    await db.commit()
    
    #triggers background verification
    background_tasks.add_task(verify_volunteer_post_ml, post.id, start_image_url)
    
    #CRITICAL FIX: Re-fetch with relationships
    # (without this, FastAPI crashes when trying to serialize 'author', 'comments', etc.)
    query = (
        select(models.Post)
        .options(
            selectinload(models.Post.author),
            selectinload(models.Post.likes),
            selectinload(models.Post.comments).selectinload(models.Comment.author),
            selectinload(models.Post.resolved_by),
            selectinload(models.Post.volunteer) # Load volunteer too
        )
        .where(models.Post.id == post_id)
    )
    result = await db.execute(query)
    return result.scalars().first()


# SUBMIT PROOF (Clock Out) 
@router.post("/{post_id}/submit_proof", response_model=schemas.Post)
async def submit_cleanup_proof(
    post_id: int,
    end_image_url: str = Body(..., embed=True), # Expect JSON: {"end_image_url": "..."}
    db: AsyncSession = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
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

    #clculate Duration
    end_time = datetime.now(timezone.utc)
    #ensures start_time is aware
    start_time = post.volunteer_start_timestamp.replace(tzinfo=timezone.utc) if post.volunteer_start_timestamp else None
    
    duration_min = 0
    if start_time:
        diff = end_time - start_time
        duration_min = int(diff.total_seconds() / 60) # Minutes
    
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
    return result.scalars().first()


# APPROVE & PAY (Resolution) 
@router.post("/{post_id}/approve", response_model=schemas.Post)
async def approve_work(
    post_id: int,
    final_points: int = Body(..., embed=True),
    db: AsyncSession = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
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
    if post.author_id != current_user.id:
         raise HTTPException(status_code=403, detail="Only author can approve")
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
    return result.scalars().first()