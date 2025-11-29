# backend/schemas.py

from pydantic import BaseModel, EmailStr
from typing import Optional, List
from datetime import datetime
from models import TaskStatus

class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    username: Optional[str] = None

# --- User Schemas ---
class UserBase(BaseModel):
    username: str
    email: EmailStr

class UserCreate(UserBase):
    password: str

# SAFE User Schema (For Leaderboards/Feed)
class UserPublic(BaseModel):
    username: str
    points: int
    class Config:
        from_attributes = True

# FULL User Schema (For /me endpoint)
class User(UserBase):
    id: int
    points: int
    created_at: datetime
    # is_active REMOVED

    class Config:
        from_attributes = True

# --- Comment & Like ---
class CommentBase(BaseModel):
    content: str

class CommentCreate(CommentBase):
    pass

class Comment(CommentBase):
    id: int
    author_id: int
    post_id: int
    created_at: datetime
    author: Optional[UserPublic] = None # Use safe user here
    class Config:
        from_attributes = True

class Like(BaseModel):
    user_id: int
    post_id: int
    class Config:
        from_attributes = True

# --- Post ---
class PostBase(BaseModel):
    image_url: str
    image_public_id: str
    caption: Optional[str] = None
    latitude: float
    longitude: float

class PostCreate(PostBase):
    pass

class Post(PostBase):
    id: int
    status: TaskStatus
    proof_image_url: Optional[str] = None
    created_at: datetime
    author_id: int
    resolved_by_id: Optional[int] = None
    
    author: Optional[UserPublic] = None     # Use safe user
    resolved_by: Optional[UserPublic] = None # Use safe user
    
    comments: List[Comment] = []
    likes: List[Like] = []

    class Config:
        from_attributes = True