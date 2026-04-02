"""
    File: backend/auth/utils/jwt.py
    Description: 
        Module for auth/utils/jwt.py functionality.
"""

'''
Access token    JWT, contains user_id, expires in 15 min
Refresh token    random string, NOT a JWT
                 raw token sent to Flutter
                 only the hash stored in DB
                 if DB is ever leaked, tokens are useless
'''
from datetime import datetime, timedelta
from jose import JWTError, jwt
from dotenv import load_dotenv
import os
import secrets
import hashlib

load_dotenv()

SECRET_KEY = os.getenv("JWT_SECRET")
ALGORITHM  = os.getenv("JWT_ALGORITHM")
ACCESS_TOKEN_EXPIRE_MINUTES  = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES"))
REFRESH_TOKEN_EXPIRE_DAYS    = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS"))


def create_access_token(user_id: str) -> str:
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": user_id,
        "exp": expire,
        "type": "access"
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_access_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("type") != "access":
            raise JWTError("Invalid token type")
        return payload
    except JWTError:
        return None


def create_refresh_token() -> str:
    # not a JWT — just a random secret string
    return secrets.token_urlsafe(64)


def hash_refresh_token(token: str) -> str:
    # never store raw refresh token in DB, store its hash
    return hashlib.sha256(token.encode()).hexdigest()

