"""
    File: backend/crud.py
    Description: 
        Contains the Create, Read, Update, and Delete (CRUD) utility functions for the 
        application. This acts as the Data Access Layer, cleanly separating database 
        query logic from the API routing logic.

    Key Operations:
        - User Lookups: Fetch users by ID, email, or username.
        - Post Lookups: Retrieve individual cleanup posts.
        - Comment Management: Creates and fetches comments linked to specific posts.

    Technical Notes:
        - Async Execution: Fully utilizes SQLAlchemy 2.0+ asynchronous sessions 
        (`AsyncSession` and `await db.execute`).
        - Relationship Loading: Uses `selectinload` extensively to eagerly load related 
        data (like a Comment's Author). This is a critical pattern in async SQLAlchemy 
        to prevent lazy-loading crashes when Pydantic attempts to serialize the data.
"""

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload # <--- Imported for relationship loading
from auth.models import User
import models, schemas

# --- USER OPERATIONS ---

async def get_user(db: AsyncSession, user_id: str):
    query = select(User).where(User.id == user_id)
    result = await db.execute(query)
    return result.scalars().first()

async def get_user_by_email(db: AsyncSession, email: str):
    query = select(User).where(User.email == email)
    result = await db.execute(query)
    return result.scalars().first()

async def get_user_by_username(db: AsyncSession, username: str):
    query = select(User).where(User.username == username)
    result = await db.execute(query)
    return result.scalars().first()

# --- POST OPERATIONS  ---

async def get_post(db: AsyncSession, post_id: str):
    query = select(models.Post).where(models.Post.id == post_id)
    result = await db.execute(query)
    return result.scalars().first()

# --- COMMENT OPERATIONS ---

async def create_comment(db: AsyncSession, comment: schemas.CommentCreate, user_id: str, post_id: str):
    db_comment = models.Comment(
        content=comment.content,
        author_id=user_id,
        post_id=post_id
    )
    db.add(db_comment)
    await db.commit()
    await db.refresh(db_comment)
    
    # --- CRITICAL FIX FOR COMMENTS ---
    # We must reload the comment with the Author attached.
    # Otherwise, Pydantic tries to read 'comment.author' and crashes the async session.
    query = (
        select(models.Comment)
        .options(selectinload(models.Comment.author))
        .where(models.Comment.id == db_comment.id)
    )
    result = await db.execute(query)
    return result.scalars().first()

async def get_comments_by_post(db: AsyncSession, post_id: str):
    query = (
        select(models.Comment)
        .where(models.Comment.post_id == post_id)
        .options(selectinload(models.Comment.author)) # Load author name for UI
        .order_by(models.Comment.created_at.desc())
    )
    result = await db.execute(query)
    return result.scalars().all()