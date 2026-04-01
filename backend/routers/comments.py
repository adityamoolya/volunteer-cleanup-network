"""
    File: backend/routers/comments.py
    Description: 
        Endpoints for adding, retrieving, and managing comments on posts.
"""

# backend/routers/comments.py

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

import schemas, crud, models
from database import get_db
from sqlalchemy import select
from auth.dependencies import get_current_user
from auth.models import User

router = APIRouter(
    prefix="/comments",
    tags=["Comments"]
)

# --- Create Comment ---
@router.post("/", response_model=schemas.Comment)
async def create_comment(
    post_id: str,
    comment: schemas.CommentCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # 1. Verify post exists
    db_post = await crud.get_post(db, post_id=post_id)
    if not db_post:
        raise HTTPException(status_code=404, detail="Post not found")

    # 2. Create comment (FIXED ARGUMENTS)
    return await crud.create_comment(
        db=db, 
        comment=comment,           # Matches crud.py definition
        user_id=current_user.id,   # Matches crud.py definition (not author_id)
        post_id=post_id
    )

# --- Get Comments for a Post ---
@router.get("/", response_model=List[schemas.Comment])
async def read_comments(
    post_id: str,
    db: AsyncSession = Depends(get_db)
):
    return await crud.get_comments_by_post(db, post_id=post_id)


# --- Delete Comment ---
@router.delete("/{comment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_comment(
    comment_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    result = await db.execute(select(models.Comment).where(models.Comment.id == comment_id))
    comment = result.scalars().first()
    
    if not comment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Comment not found")
        
    if comment.author_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to delete this comment")
        
    await db.delete(comment)
    await db.commit()
    
    return None