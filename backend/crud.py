# backend/crud.py

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload # <--- Imported for relationship loading
from passlib.context import CryptContext
import models, schemas

# Setup password hashing (Argon2)
pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")

def get_password_hash(password):
    return pwd_context.hash(password)

# --- USER OPERATIONS ---

async def get_user(db: AsyncSession, user_id: int):
    query = select(models.User).where(models.User.id == user_id)
    result = await db.execute(query)
    return result.scalars().first()

async def get_user_by_email(db: AsyncSession, email: str):
    query = select(models.User).where(models.User.email == email)
    result = await db.execute(query)
    return result.scalars().first()

async def get_user_by_username(db: AsyncSession, username: str):
    query = select(models.User).where(models.User.username == username)
    result = await db.execute(query)
    return result.scalars().first()

async def create_user(db: AsyncSession, user: schemas.UserCreate):
    hashed_password = get_password_hash(user.password)
    db_user = models.User(
        username=user.username,
        email=user.email,
        hashed_password=hashed_password,
        points=0
    )
    db.add(db_user)
    await db.commit()
    await db.refresh(db_user)
    return db_user

# --- POST OPERATIONS (This was missing!) ---

async def get_post(db: AsyncSession, post_id: int):
    query = select(models.Post).where(models.Post.id == post_id)
    result = await db.execute(query)
    return result.scalars().first()

# --- COMMENT OPERATIONS ---

async def create_comment(db: AsyncSession, comment: schemas.CommentCreate, user_id: int, post_id: int):
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

async def get_comments_by_post(db: AsyncSession, post_id: int):
    query = (
        select(models.Comment)
        .where(models.Comment.post_id == post_id)
        .options(selectinload(models.Comment.author)) # Load author name for UI
        .order_by(models.Comment.created_at.desc())
    )
    result = await db.execute(query)
    return result.scalars().all()