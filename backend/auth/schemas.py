"""
    File: backend/auth/schemas.py
    Description: 
        Pydantic models for authentication-related data validation and serialization.
"""

'''
## What Each Schema Does
RegisterRequest     →  email + password coming in
LoginRequest        →  same shape, separate for clarity
RefreshRequest      →  just the refresh token
LogoutRequest       →  just the refresh token
FirebaseAuthRequest →  firebase token + optional device info

TokenResponse       →  what we return after login/refresh
UserResponse        →  what we return for /me route
MessageResponse     →  generic { "message": "..." } responses
'''

from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime


#Request Schemas 

class RegisterRequest(BaseModel):
    email: EmailStr
    username: str
    password: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: str


class FirebaseAuthRequest(BaseModel):
    firebase_token: str
    device_info: Optional[str] = None


#Response Schemas 

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class UserResponse(BaseModel):
    id: str
    email: str
    username: str
    # is_banned: bool
    points: int
    created_at: datetime

    class Config:
        from_attributes = True


class MessageResponse(BaseModel):
    message: str

