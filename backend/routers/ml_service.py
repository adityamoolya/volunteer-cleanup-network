import os
import httpx
import logging
from sqlalchemy import select
from database import AsyncSessionLocal
import models

logger = logging.getLogger(__name__)
CLASSIFIER_MICORSERVICE = os.getenv("CLASSIFIER_MICORSERVICE") 
ML_URL = f"{CLASSIFIER_MICORSERVICE}/predict_with_urls"

async def process_post_ml(post_id: str, image_url: str):
    """Background task to analyze the initial post image."""
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(ML_URL, json={"image_url": image_url}, timeout=30.0)
            
        if resp.status_code == 200:
            data = resp.json()
            pred_class = data.get("predicted_class", "Unknown") 
            points = int(data.get("points", 0))         
            
            async with AsyncSessionLocal() as db:
                result = await db.execute(select(models.Post).where(models.Post.id == post_id))
                post = result.scalars().first()
                if post:
                    post.predicted_class = pred_class
                    post.points = points
                    await db.commit()
    except Exception as e:
        logger.error(f"ML Service Error: {e}")
        

async def verify_volunteer_post_ml(post_id: str, image_url: str):
    try:
        async with httpx.AsyncClient() as client:
            # call the same ML service to check the new photo
            resp = await client.post(ML_URL, json={"image_url": image_url}, timeout=30.0)
            
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
