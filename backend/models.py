# backend/models.py

from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text, Float, Enum
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base
import enum

class TaskStatus(str, enum.Enum):
    OPEN = "open"
    PENDING_VERIFICATION = "pending"
    COMPLETED = "completed"

class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True)
    email = Column(String(100), unique=True, index=True)
    hashed_password = Column(String(255))
    # is_active REMOVED
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    points = Column(Integer, default=0)
    
    posts = relationship("Post", back_populates="author", foreign_keys="Post.author_id")
    contribution_tasks = relationship("Post", back_populates="resolved_by", foreign_keys="Post.resolved_by_id")
    comments = relationship("Comment", back_populates="author")
    likes = relationship("Like", back_populates="user")

class Post(Base):
    __tablename__ = "posts"

    id = Column(Integer, primary_key=True, index=True)
    
    image_url = Column(String(500), nullable=False)
    image_public_id = Column(String(255), nullable=False)
    caption = Column(Text, nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    
    status = Column(Enum(TaskStatus), default=TaskStatus.OPEN)
    proof_image_url = Column(String(500), nullable=True)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    author_id = Column(Integer, ForeignKey("users.id"))
    resolved_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    
    author = relationship("User", back_populates="posts", foreign_keys=[author_id])
    resolved_by = relationship("User", back_populates="contribution_tasks", foreign_keys=[resolved_by_id])
    
    comments = relationship("Comment", back_populates="post", cascade="all, delete")
    likes = relationship("Like", back_populates="post", cascade="all, delete")

class Comment(Base):
    __tablename__ = "comments"
    
    id = Column(Integer, primary_key=True, index=True)
    content = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    author_id = Column(Integer, ForeignKey("users.id"))
    post_id = Column(Integer, ForeignKey("posts.id"))
    
    author = relationship("User", back_populates="comments")
    post = relationship("Post", back_populates="comments")

class Like(Base):
    __tablename__ = "likes"
    
    id = Column(Integer, primary_key=True, index=True)
    
    user_id = Column(Integer, ForeignKey("users.id"))
    post_id = Column(Integer, ForeignKey("posts.id"))
    
    user = relationship("User", back_populates="likes")
    post = relationship("Post", back_populates="likes")