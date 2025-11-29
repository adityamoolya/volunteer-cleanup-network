# routers/auth.py

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
# --- MODIFIED: Import AsyncSession for type hinting ---
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import timedelta
from typing import Annotated

import schemas, crud
from database import get_db
from auth_utils import (
    authenticate_user, 
    create_access_token, 
    get_current_active_user,
    get_password_hash
)

router = APIRouter(tags=["Authentication"])

# Login endpoint
@router.post("/token", response_model=schemas.Token)
async def login_for_access_token(
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
    # --- MODIFIED: Switched to AsyncSession ---
    db: AsyncSession = Depends(get_db)
):
    # --- MODIFIED: Added await for the async function ---
    user = await authenticate_user(db, form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=30)
    access_token = create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

# --- MODIFIED: This function is now async ---
@router.post("/register", response_model=schemas.User)
async def register_user(user: schemas.UserCreate, db: AsyncSession = Depends(get_db)):
    # --- MODIFIED: Added await for the async function ---
    db_user = await crud.get_user_by_username(db, username=user.username)
    if db_user:
        raise HTTPException(status_code=400, detail="Username already registered")
    
    # --- MODIFIED: Added await for the async function ---
    db_user = await crud.get_user_by_email(db, email=user.email)
    if db_user:
        raise HTTPException(status_code=400, detail="Email already registered")
    
    # --- MODIFIED: Added await for the async function ---
    return await crud.create_user(db=db, user=user)

# Get current user
# @router.get("/users/me/", response_model=schemas.User)
# async def read_users_me(
#     current_user: Annotated[schemas.User, Depends(get_current_active_user)]
# ):
#     return current_user