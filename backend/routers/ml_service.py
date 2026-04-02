'''
    File: backend/routers/ml_service.py
    Description: 
        Provides integration with the machine learning service for image verification.
        Sends classification requests asynchronously and handles retries or failures.
'''

import os
import httpx
import logging
from sqlalchemy import select
from database import AsyncSessionLocal
import models

logger = logging.getLogger(__name__)
CLASSIFIER_MICORSERVICE = os.getenv("CLASSIFIER_MICORSERVICE") 
ML_URL = f"{CLASSIFIER_MICORSERVICE}/predict_with_urls"

from routers.notification_service import notify_user_async
from sqlalchemy.orm import selectinload

async def process_post_ml(post_id: str, image_url: str):
    """Background task to analyze the initial post image."""
    error_msg = None
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(ML_URL, json={"image_url": image_url}, timeout=30.0)
            
        if resp.status_code == 200:
            data = resp.json()
            pred_class = data.get("predicted_class", "Unknown") 
            points = int(data.get("points", 0))         
            
            async with AsyncSessionLocal() as db:
                result = await db.execute(select(models.Post).options(selectinload(models.Post.author)).where(models.Post.id == post_id))
                post = result.scalars().first()
                if post:
                    post.predicted_class = pred_class
                    post.points = points
                    await db.commit()
                    if post.author:
                        await notify_user_async(db, post.author, "Verification Complete", f"Your task was classified as {pred_class} ({points} pts).")
        else:
            error_msg = f"HTTP {resp.status_code}"
    except Exception as e:
        logger.error(f"ML Service Error: {e}")
        error_msg = str(e)
        
    if error_msg:
        async with AsyncSessionLocal() as db:
            result = await db.execute(select(models.Post).options(selectinload(models.Post.author)).where(models.Post.id == post_id))
            post = result.scalars().first()
            if post:
                post.predicted_class = "Classification Failed"
                await db.commit()
                if post.author:
                    await notify_user_async(db, post.author, "Alert", "Our AI failed to classify your photo. Please try again.")

async def verify_volunteer_post_ml(post_id: str, image_url: str):
    error_msg = None
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(ML_URL, json={"image_url": image_url}, timeout=30.0)
            
        if resp.status_code == 200:
            data = resp.json()
            points = int(data.get("points", 0))         
            
            async with AsyncSessionLocal() as db:
                result = await db.execute(select(models.Post).options(selectinload(models.Post.volunteer)).where(models.Post.id == post_id))
                post = result.scalars().first()
                if post:
                    post.verified_points = points 
                    await db.commit()
                    logger.info(f"[Verification-----] Post {post_id} check: ML found {points} pts")
                    
                    if post.volunteer:
                        await notify_user_async(db, post.volunteer, "Verification Routine", f"Our system graded your cleanup proof at {points} pts.")
        else:
            error_msg = f"HTTP {resp.status_code}"
    except Exception as e:
        logger.error(f"[Verification-----] Error: {e}")
        error_msg = str(e)

    if error_msg:
         async with AsyncSessionLocal() as db:
                result = await db.execute(select(models.Post).options(selectinload(models.Post.volunteer)).where(models.Post.id == post_id))
                post = result.scalars().first()
                if post and post.volunteer:
                    await notify_user_async(db, post.volunteer, "Alert", "Our AI could not grade your cleanup photo automatically. It requires manual review.")
