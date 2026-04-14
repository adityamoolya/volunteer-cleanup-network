'''
    File: backend/schemas.py
    Description: 
        Defines the Pydantic models used for data validation, serialization, and 
        deserialization. This acts as the bridge between the raw SQLAlchemy database 
        models and the JSON payloads sent to/from the API endpoints.

    Key Schemas:
        - User Schemas: Differentiates between `UserPublic` (safe for leaderboards/feeds, 
        strips emails/passwords) and `User` (full details for the `/me` endpoint).
        - Post Schemas: Manages the data required to create (`PostCreate`), update 
        (`PostUpdate`), and read (`Post`) cleanup missions. Includes fields for ML 
        predictions, location tracking, and phase 1/2/3 image URLs.
        - Interaction Schemas: Defines structures for Comments and Likes.
        - Admin & Reward Schemas: Manages admin operations, user ban requests, and the gamified rewards catalog.

    Security Note:
        By utilizing `UserPublic` as nested models inside `Post` and `Comment`, the 
        API guarantees that sensitive user data is never accidentally leaked to the 
        public feed.
'''

from pydantic import BaseModel, EmailStr
from typing import Optional, List, Dict
from datetime import datetime
from models import TaskStatus

# --- User Schemas ---

# SAFE User Schema (For Leaderboards/Feed)
class UserPublic(BaseModel):
    username: str
    points: int
    class Config:
        from_attributes = True

# FULL User Schema (For /me endpoint and protected routes)
class User(BaseModel):
    id: str
    email: EmailStr
    username: str
    points: int
    created_at: datetime

    class Config:
        from_attributes = True

# --- Comment & Like ---
class CommentBase(BaseModel):
    content: str

class CommentCreate(CommentBase):
    content: str

class Comment(CommentBase):
    id: str
    author_id: str
    post_id: str
    created_at: datetime
    author: Optional[UserPublic] = None # Use safe user here
    class Config:
        from_attributes = True

class Like(BaseModel):
    user_id: str
    post_id: str
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
    predicted_class: Optional[str] = "Processing..."
    all_probabilities: Optional[Dict[str, str]] = None
    points: Optional[int] = 0


class PostUpdate(BaseModel):
    predicted_class: Optional[str] = None
    points: Optional[int] = None
    caption: Optional[str] = None

    
class Post(PostBase):
    id: str
    status: TaskStatus
    proof_image_url: Optional[str] = None
    created_at: datetime
    author_id: str
    resolved_by_id: Optional[str] = None
    predicted_class: Optional[str] = None 
    all_probabilities: Optional[Dict[str, str]] = None
    points: int

    volunteer_id: Optional[str] = None
    start_image_url: Optional[str] = None
    end_image_url: Optional[str] = None
    volunteer_start_timestamp: Optional[datetime] = None
    volunteer_end_timestamp: Optional[datetime] = None
    cleanup_duration_minutes: Optional[int] = None
    verified_points: Optional[int] = None
    volunteer: Optional[UserPublic] = None # To see who cleaned it

    author: Optional[UserPublic] = None     # Use safe user
    resolved_by: Optional[UserPublic] = None # Use safe user
    comments: List[Comment] = []
    likes: List[Like] = []

    class Config:
            from_attributes = True

class BanRequest(BaseModel):
    ban: bool
    reason: Optional[str] = None   # ignored on unban, stored for context on ban


class UserAdminView(BaseModel):
    id: str
    username: str
    email: str
    points: int
    is_banned: bool

    class Config:
        from_attributes = True

# --- Reward Schemas ---
class RewardBase(BaseModel):
    name: str
    description: Optional[str] = None
    image_url: Optional[str] = None  # Cloudinary brand logo URL
    cost_in_points: int
    stock: int

class RewardCreate(RewardBase):
    pass

class Reward(RewardBase):
    id: str
    created_at: datetime
    class Config:
        from_attributes = True

# --- Redemption Schemas ---
class RedemptionRequestBase(BaseModel):
    reward_id: str

class RedemptionRequestItem(BaseModel):
    id: str
    user_id: str
    reward_id: str
    status: str
    created_at: datetime
    updated_at: Optional[datetime] = None
    reward: Optional[Reward] = None
    class Config:
        from_attributes = True

class RewardReviewRequest(BaseModel):
    approve: bool