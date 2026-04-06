''' 
    File: backend/models.py
    Description: 
        Defines the core relational database schema . This handles the primary user-generated 
        content and the lifecycle of a cleanup mission.

    Key Models:
        - Post: Represents a cleanup request. Tracks the 3-phase lifecycle:
            1. Author posts the request (Open).
            2. Volunteer arrives and clocks in (In Progress).
            3. Volunteer uploads proof and clocks out (Pending Approval/Completed).
        - Comment: Represents user comments on a specific post.
        - Like: Represents user likes on a specific post.
        - TaskStatus (Enum): Restricts post status to predefined lifecycle states.

    Relationships:
        - Integrates tightly with `auth.models.User` to track authors, active 
        volunteers, and the user who resolved the task.
        - Uses cascade deletions (deleting a Post automatically deletes its Comments/Likes).

'''
import uuid
from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text, Float, Enum, JSON
from sqlalchemy.orm import relationship, backref
from sqlalchemy.sql import func
from database import Base
from auth.models import User  # User now lives in auth module
import enum

class TaskStatus(str, enum.Enum):
    OPEN = "open"
    IN_PROGRESS = "in_progress"       # volunteer is on site (Clocked In)
    PENDING_APPROVAL = "pending"      # work done, waiting for author (Clocked Out)
    COMPLETED = "completed"           # points paid
    CANCELLED = "cancelled"           # if volunteer decides to cancel 

class Post(Base):
    __tablename__ = "posts"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()), index=True)
    #phase 1---author posts request 
    image_url = Column(String(500), nullable=False)
    image_public_id = Column(String(255), nullable=False)
    caption = Column(Text, nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    
    predicted_class = Column(String(50), nullable=True)
    all_probabilities = Column(JSON, nullable=True)  # {"Battery": "0.12%", "Plastic": "87.32%", ...}
    points = Column(Integer, default=0)
    status = Column(Enum(TaskStatus), default=TaskStatus.OPEN)
    
    author_id = Column(String(36), ForeignKey("users.id"))
    author = relationship("User", back_populates="posts", foreign_keys=[author_id])

    #Phase 2---- volunteer arrival (Clock In) 
    volunteer_id = Column(String(36), ForeignKey("users.id"), nullable=True)
    volunteer = relationship("User", back_populates="volunteer_tasks", foreign_keys=[volunteer_id])
    
    start_image_url = Column(String(500), nullable=True)        #the "before" photo taken my volunteer
    volunteer_start_timestamp = Column(DateTime(timezone=True), nullable=True)
    verified_points = Column(Integer, nullable=True)            # ML V2 result (variation check)

    #Phase 3-- cleanup & proof (Clock Out)
    end_image_url = Column(String(500), nullable=True)          # the "after" photo basically proof
    volunteer_end_timestamp = Column(DateTime(timezone=True), nullable=True)
    cleanup_duration_minutes = Column(Integer, nullable=True)   # calculated duration
    
    proof_image_url = Column(String(500), nullable=True)
    resolved_by_id = Column(String(36), ForeignKey("users.id"), nullable=True)
    resolved_by = relationship("User", back_populates="contribution_tasks", foreign_keys=[resolved_by_id])
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    comments = relationship("Comment", back_populates="post", cascade="all, delete")
    likes = relationship("Like", back_populates="post", cascade="all, delete")


class Comment(Base):
    __tablename__ = "comments"
    
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()), index=True)
    content = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    author_id = Column(String(36), ForeignKey("users.id"))
    post_id = Column(String(36), ForeignKey("posts.id"))
    
    author = relationship("User", back_populates="comments")
    post = relationship("Post", back_populates="comments")

class Like(Base):
    __tablename__ = "likes"
    
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()), index=True)
    
    user_id = Column(String(36), ForeignKey("users.id"))
    post_id = Column(String(36), ForeignKey("posts.id"))
    user = relationship("User", back_populates="likes")
    post = relationship("Post", back_populates="likes")

class RedemptionStatus(str, enum.Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"

class Reward(Base):
    __tablename__ = "rewards"
    
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()), index=True)
    name = Column(String(100), nullable=False)
    description = Column(Text, nullable=True)
    cost_in_points = Column(Integer, nullable=False)
    stock = Column(Integer, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class RedemptionRequest(Base):
    __tablename__ = "redemption_requests"
    
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()), index=True)
    user_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    reward_id = Column(String(36), ForeignKey("rewards.id", ondelete="CASCADE"), nullable=False)
    status = Column(Enum(RedemptionStatus), default=RedemptionStatus.PENDING)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    user = relationship("User", backref=backref("redemption_requests", cascade="all, delete-orphan"))
    reward = relationship("Reward", backref=backref("requests", cascade="all, delete-orphan"))

