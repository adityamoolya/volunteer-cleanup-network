# backend/routers/posts.py

from urllib.parse import urljoin
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status, UploadFile, File
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
CLASSIFIER_MICORSERVICE = os.getenv("CLASSIFIER_MICORSERVICE") 
print(CLASSIFIER_MICORSERVICE+"============================================================")
ml_url = urljoin(CLASSIFIER_MICORSERVICE, "/predict_with_urls")
print(CLASSIFIER_MICORSERVICE+"============================================================")



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
            print("ML SERVICE RESPONSE",data,"=-=-=-=--===========-=-=====--=----------------=") 
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
                    print(f"[Background-----] Post {post_id} updated: {pred_class} ({points} pts)")
        else:
            print(f" [Background-----] ML Service returned {resp.status_code}")

    except Exception as e:
        print(f"[Background-----] ML Error: {e}")

# CREATE REQUEST , tb accessed by author only
@router.post("/", response_model=schemas.Post, status_code=status.HTTP_201_CREATED)
async def create_request(
    post_data: schemas.PostCreate,
    background_tasks: BackgroundTasks, # inject backgroundtasks
    db: AsyncSession = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user)
):
    #create Post with "Processing" state
    new_post = models.Post(
        image_url=post_data.image_url,
        image_public_id=post_data.image_public_id,
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
        # post.resolved_by.points += 50
        post.resolved_by.points += post.points
    
    post.status = models.TaskStatus.COMPLETED
    
    await db.commit()
    return {"message": "Task approved! Points awarded."}

# async def calculate_points(image_url: str, public_id: str):
#     try:
#         async with httpx.AsyncClient(timeout=20.0) as client:
#             response = await client.post(
#                 CLASSIFIER_MICORSERVICE,
#                 json={
#                     "image_url": image_url
#                 }
#             )

#         response.raise_for_status()  # raises if http respomse 4xx / 5xx , does nothing for 200
#         return response.json()       # return microservice response

#     except httpx.RequestError as e:
#         raise HTTPException(
#             status_code=status.HTTP_502_BAD_GATEWAY,
#             detail=f"Classifier is unreachble: {e}"
#         )
        

#     except httpx.HTTPStatusError as e:
#         raise HTTPException(
#             status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
#             detail=f"Classifier is but bad response {e}"
#         )