# backend/routers/comments.py

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

import schemas, crud
from database import get_db
from auth_utils import get_current_active_user

router = APIRouter(
    prefix="/comments",
    tags=["Comments"]
)

# --- Create Comment ---
@router.post("/", response_model=schemas.Comment)
async def create_comment(
    post_id: int,
    comment: schemas.CommentCreate,
    db: AsyncSession = Depends(get_db),
    current_user: schemas.User = Depends(get_current_active_user)
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
    post_id: int,
    db: AsyncSession = Depends(get_db)
):
    return await crud.get_comments_by_post(db, post_id=post_id)