# Auth Module

A self-contained, reusable authentication system built with FastAPI. Drop it into any project and follow this guide to get it running.

---

## What's Inside

```
auth/
├── models.py          ->  User, RefreshToken, OAuthAccount, Admin tables
├── schemas.py         ->  Pydantic request/response shapes
├── dependencies.py    ->  get_current_user() Depends() guard
├── redis_client.py    ->  Upstash Redis connection
├── routers/
│   ├── auth.py        ->  /auth/register, /login, /refresh, /logout, /me
│   └── oauth.py       ->  /oauth/github (Supabase OAuth bridge)
└── utils/
    ├── jwt.py         ->  create/decode access token, create/hash refresh token
    ├── hashing.py     ->  bcrypt hash + verify
    └── oauth_verify.py ->  Supabase JWT verification
```

---

## Features

- Email + password auth
- Stateful JWT with refresh token rotation
- Instant token revocation via Redis
- GitHub OAuth via Supabase (swap provider anytime)
- Ban system (`is_banned` flag, checked on every authenticated request)
- Admin role system (separate Admin table, router-level dependency guard)
- Fully async (`asyncpg` + SQLAlchemy async)
- Postgres ready, SQLite for local dev
- Firebase push notification integration (FCM token stored per user, stale tokens auto-cleaned)

---

## Requirements

Add these to your project's `requirements.txt`:

```
fastapi
uvicorn
sqlalchemy
python-jose[cryptography]
python-dotenv
upstash-redis
authlib
httpx
aiosqlite
pydantic[email]
asyncpg
bcrypt
firebase-admin
```

---

## Step 1 -- Copy auth/ into your project

```
your_project/
├── auth/           <- paste here
├── your_app/
├── main.py
├── database.py
└── .env
```

---

## Step 2 -- database.py (project root)

Your project needs this file at root. If it already exists, make sure it has:

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from dotenv import load_dotenv
import os

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

if DATABASE_URL.startswith("postgresql"):
    DATABASE_URL = DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://")
elif DATABASE_URL.startswith("sqlite"):
    DATABASE_URL = DATABASE_URL.replace("sqlite:///", "sqlite+aiosqlite:///")

engine = create_async_engine(DATABASE_URL, echo=False)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False
)

Base = declarative_base()

async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
```

---

## Step 3 -- .env

```env
# Database
DATABASE_URL=sqlite:///./dev.db                          # local dev
# DATABASE_URL=postgresql://user:pass@host:5432/dbname  # production

# JWT
JWT_SECRET=your_random_secret_here
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30

# Upstash Redis
UPSTASH_REDIS_URL=https://xxx.upstash.io
UPSTASH_REDIS_TOKEN=your_token_here

# Supabase (for OAuth)
SUPABASE_JWT_SECRET=your_supabase_jwt_secret
SUPABASE_URL=https://xxxx.supabase.co
```

---

## Step 4 -- main.py

Mount the auth routers in your project's main.py:

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from database import Base, engine
from auth.models import User, RefreshToken, OAuthAccount
from auth.routers import auth, oauth

@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],        # lock down in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# mount auth
app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(oauth.router, prefix="/oauth", tags=["oauth"])

# your other routers go here
# app.include_router(products.router, prefix="/products", tags=["products"])
```

---

## Step 5 -- Protecting Your Own Routes

Use `get_current_user` as a dependency on any route you want to protect:

```python
from auth.dependencies import get_current_user
from auth.models import User
from fastapi import Depends

@router.get("/your-protected-route")
async def protected(current_user: User = Depends(get_current_user)):
    return {"user_id": current_user.id}
```

That's it. The dependency handles:
- Extracting Bearer token from header
- Validating JWT signature
- Checking user exists in DB
- Checking `is_banned` flag
- Returning user object to your route

---

## Step 6 -- Run It

```bash
uvicorn main:app --reload
```

Check:
```
http://localhost:8000/health   ->  { "status": "ok" }
http://localhost:8000/docs     ->  Swagger UI with all auth routes
```

---

## External Services Setup

### Supabase (Postgres + OAuth)
```
supabase.com -> new project
Settings -> Database -> copy URI -> paste as DATABASE_URL
Settings -> JWT Keys -> reveal Legacy JWT Secret -> paste as SUPABASE_JWT_SECRET
Authentication -> Providers -> GitHub -> enable -> paste GitHub OAuth credentials
```

### GitHub OAuth App
```
github.com -> Settings -> Developer Settings -> OAuth Apps -> New OAuth App
Homepage URL        -> your app URL
Callback URL        -> https://your-project.supabase.co/auth/v1/callback
Copy Client ID + Secret -> paste into Supabase GitHub provider
```

### Upstash Redis
```
upstash.com -> new Redis database
Copy REST URL  -> paste as UPSTASH_REDIS_URL
Copy REST Token -> paste as UPSTASH_REDIS_TOKEN
```

---

## Auth Flow Reference

### Email/Password
```
POST /auth/register     { email, password }           -> 201
POST /auth/login        { email, password }           -> { access_token, refresh_token }
GET  /auth/me           Bearer <access_token>         -> user object
POST /auth/refresh      { refresh_token }             -> { access_token, refresh_token }
POST /auth/logout       { refresh_token }             -> 200
```

### GitHub OAuth
```
1. Flutter/Web -> Supabase Auth -> GitHub -> returns Supabase session
2. Extract session.access_token
3. POST /oauth/github   { firebase_token: supabase_access_token }
4. Returns your own { access_token, refresh_token }
5. Your system takes over completely from here
```

---

## Token Lifecycle

```
Access token    ->  JWT, 15 min TTL, stateless, no DB check per request
Refresh token   ->  random string, 30 day TTL, stored hashed in Postgres + Redis
                    Redis  -> fast lookup on every refresh call
                    Postgres -> audit log, survives Redis flush

On refresh      ->  old token revoked, new token issued (rotation)
On logout       ->  Redis key deleted instantly, Postgres marked revoked
On ban          ->  set is_banned=True on user row, blocked on next request
```

---

## Swapping OAuth Provider

Only two things change when switching from GitHub to any other provider:

```
1. Supabase Dashboard -> Authentication -> Providers -> enable new provider
2. POST /oauth/github rename to /oauth/google (or keep generic)
```

Zero changes inside auth/ code. The Supabase JWT verification works the same regardless of provider.

---

## Local Dev vs Production Checklist

```
Local dev
├── DATABASE_URL=sqlite:///./dev.db
├── JWT_SECRET=anything
└── CORS allow_origins=["*"]

Production
├── DATABASE_URL=postgresql://...
├── JWT_SECRET=long random string (32+ chars)
├── CORS allow_origins=["https://yourdomain.com"]
└── Never commit .env or serviceAccountKey.json
```

---

## Files That Never Go Into Git

```
.env
serviceAccountKey.json   (if using Firebase)
*.db                     (SQLite local files)
```

Make sure these are in `.gitignore`.
