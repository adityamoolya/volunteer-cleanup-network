"""
    File: backend/auth/models.py
    Description: 
        Defines the database models related to authentication (Users, Admins, etc.).
"""

from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, Text, Integer
from sqlalchemy.orm import relationship
from database import Base
import uuid
from datetime import datetime


def generate_uuid():
    return str(uuid.uuid4())


class User(Base):
    __tablename__ = "users"

    id             = Column(String, primary_key=True, default=generate_uuid)
    email          = Column(String, unique=True, nullable=False, index=True)
    username       = Column(String(50), unique=True, nullable=False, index=True)
    password_hash  = Column(String, nullable=True)    # nullable for OAuth users
    fcm_token      = Column(String, nullable=True)
    # is_banned      = Column(Boolean, default=False)
    is_banned = Column(Boolean, default=False, nullable=False)
    created_at     = Column(DateTime, default=datetime.utcnow)

    points         = Column(Integer, default=0)

    # --- Auth relationships ---
    refresh_tokens = relationship("RefreshToken", back_populates="user", cascade="all, delete-orphan")
    oauth_accounts = relationship("OAuthAccount", back_populates="user", cascade="all, delete-orphan")

    # --- App relationships ---
    posts = relationship("Post", back_populates="author", foreign_keys="Post.author_id", cascade="all, delete-orphan")
    contribution_tasks = relationship("Post", back_populates="resolved_by", foreign_keys="Post.resolved_by_id")
    volunteer_tasks = relationship("Post", back_populates="volunteer", foreign_keys="Post.volunteer_id")
    comments = relationship("Comment", back_populates="author", cascade="all, delete-orphan")
    likes = relationship("Like", back_populates="user", cascade="all, delete-orphan")
    admin_profile = relationship("Admin", back_populates="user", uselist=False, cascade="all, delete-orphan")


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id           = Column(String, primary_key=True, default=generate_uuid)
    user_id      = Column(String, ForeignKey("users.id"), nullable=False)
    token_hash   = Column(String, nullable=False, index=True)
    device_info  = Column(Text, nullable=True)
    expires_at   = Column(DateTime, nullable=False)
    is_revoked   = Column(Boolean, default=False)
    created_at   = Column(DateTime, default=datetime.utcnow)

    user         = relationship("User", back_populates="refresh_tokens")


class OAuthAccount(Base):
    __tablename__ = "oauth_accounts"

    id               = Column(String, primary_key=True, default=generate_uuid)
    user_id          = Column(String, ForeignKey("users.id"), nullable=False)
    provider         = Column(String, nullable=False)       #"google", "oidc"
    provider_user_id = Column(String, nullable=False)       #firebase UID or OIDC sub
    email            = Column(String, nullable=False)
    created_at       = Column(DateTime, default=datetime.utcnow)

    user             = relationship("User", back_populates="oauth_accounts")

class Admin(Base):
    __tablename__ = "admins"

    # Unique identifier for each admin record (separate from user_id).
    # Using UUID allows flexibility if the schema evolves beyond 1:1 mapping.
    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))

    # Foreign key reference to the users table.
    # 'unique=True' enforces that each user can only have one admin entry.
    # 'nullable=False' ensures every admin row is tied to a valid user.
    user_id = Column(String(36), ForeignKey("users.id"), unique=True, nullable=False)

    # Denormalized field storing username at the time of promotion.
    # Useful for quick access without needing a JOIN, but may become stale
    # if the username changes in the users table.
    username = Column(String(150), nullable=False)

    # ORM relationship to the User model.
    # Enables access like: admin.user → corresponding User object
    user = relationship("User")
'''
## Why `String` for UUID instead of `UUID` type
UUID type   Postgres only
String  works on SQLite + Postgres both
'''
