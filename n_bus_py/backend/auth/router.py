"""Auth endpoints — /auth/*"""

import uuid

import jwt
from fastapi import APIRouter, Depends, HTTPException

from ai_service import config
from db.operations import create_user, get_user_by_username

from . import models
from .dependencies import get_current_user
from .utils import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)

router = APIRouter()


@router.post("/login", response_model=models.TokenResponse)
async def login(req: models.LoginRequest):
    user = await get_user_by_username(req.username.strip())
    if user is None or not verify_password(req.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    access = create_access_token(user.id, user.username)
    refresh = create_refresh_token(user.id)
    return models.TokenResponse(access_token=access, refresh_token=refresh)


@router.post("/register", response_model=models.TokenResponse)
async def register(req: models.RegisterRequest):
    if not config.ALLOW_SELF_REGISTRATION:
        raise HTTPException(status_code=403, detail="Self-registration is disabled")
    username = req.username.strip()
    existing = await get_user_by_username(username)
    if existing:
        raise HTTPException(status_code=409, detail="Username already taken")
    user_id = uuid.uuid4().hex
    pw_hash = hash_password(req.password)
    await create_user(user_id, username, pw_hash)
    access = create_access_token(user_id, username)
    refresh = create_refresh_token(user_id)
    return models.TokenResponse(access_token=access, refresh_token=refresh)


@router.post("/refresh", response_model=models.TokenResponse)
async def refresh(req: models.RefreshRequest):
    try:
        payload = decode_token(req.refresh_token)
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Refresh token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    if payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Not a refresh token")
    user = await get_user_by_username(payload["sub"])
    if user is None:
        raise HTTPException(status_code=401, detail="User not found")
    access = create_access_token(user.id, user.username)
    refresh_new = create_refresh_token(user.id)
    return models.TokenResponse(access_token=access, refresh_token=refresh_new)


@router.get("/me", response_model=models.UserResponse)
async def me(user: dict = Depends(get_current_user)):
    from db.operations import get_user_by_id
    u = await get_user_by_id(user["id"])
    return models.UserResponse(
        id=u.id,
        username=u.username,
        created_at=u.created_at,
    )
