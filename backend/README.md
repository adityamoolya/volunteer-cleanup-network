# Volunteer Cleanup Network — Backend

A **FastAPI** backend powering a community-driven trash cleanup platform. Users report waste sightings, volunteers claim and clean them up, and the system awards points — creating a gamified environmental cleanup loop.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Setup Guide](#setup-guide)
- [Environment Variables](#environment-variables)
- [API Endpoints](#api-endpoints)
- [Authentication System](#authentication-system)
- [Database Models](#database-models)
- [Volunteer Workflow](#volunteer-workflow)
- [External Services](#external-services)
- [Docker Deployment](#docker-deployment)

---

## Architecture Overview

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────┐
│  Flutter App │────>│   FastAPI     │────>│  SQLite / PgSQL  │
│  (Frontend)  │<────│   Backend     │<────│  (Database)      │
└──────────────┘     └──────┬───────┘     └──────────────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
        ┌─────┴─────┐ ┌────┴────┐ ┌──────┴──────┐
        │ Cloudinary │ │  Redis  │ │ ML Service  │
        │ (Images)   │ │(Upstash)│ │(Classifier) │
        └───────────┘ └─────────┘ └─────────────┘
```

**Tech Stack:**
- **Framework:** FastAPI (async, Python 3.12)
- **ORM:** SQLAlchemy 2.0 (async with `asyncpg` / `aiosqlite`)
- **Auth:** JWT (access tokens) + hashed refresh tokens + Redis cache
- **Image Storage:** Cloudinary (with mock mode for local dev)
- **ML Service:** External trash classifier microservice
- **Cache/Session:** Upstash Redis (serverless)
- **Database:** SQLite (local dev) / PostgreSQL (production)

---

## Project Structure

```
backend/
├── main.py                  # Application entry point & FastAPI app factory
├── database.py              # Async SQLAlchemy engine, session factory, DB config
├── models.py                # SQLAlchemy models: Post, Comment, Like
├── schemas.py               # Pydantic schemas for request/response validation
├── crud.py                  # Reusable CRUD operations (users, posts, comments)
├── .env                     # Environment variables (secrets, DB URL, API keys)
├── requirements.txt         # Python dependencies
├── Dockerfile               # Container build instructions
├── auth.db                  # SQLite database file (auto-created, gitignored)
│
├── auth/                    # ── Authentication Module ──────────────────
│   ├── __init__.py
│   ├── models.py            #   User, RefreshToken, OAuthAccount models
│   ├── schemas.py           #   Auth request/response Pydantic schemas
│   ├── dependencies.py      #   get_current_user dependency (JWT guard)
│   ├── redis_client.py      #   Upstash Redis client for refresh token cache
│   ├── SETUP.md             #   Auth module setup documentation
│   │
│   ├── routers/             #   ── Auth API Routes ──
│   │   ├── __init__.py
│   │   ├── auth.py          #     Register, Login, Refresh, Logout, /me
│   │   └── oauth.py         #     GitHub OAuth via Supabase JWT
│   │
│   └── utils/               #   ── Auth Utilities ──
│       ├── __init__.py
│       ├── jwt.py           #     JWT creation, decoding, refresh token hashing
│       ├── hashing.py       #     bcrypt password hashing & verification
│       └── oauth_verify.py  #     Supabase/GitHub token verification
│
└── routers/                 # ── Feature Routes ─────────────────────────
    ├── __init__.py
    ├── posts.py             #   Post CRUD + volunteer workflow endpoints
    ├── post_service.py      #   Business logic: feed queries, start_work
    ├── ml_service.py        #   Background tasks: ML classification calls
    ├── comments.py          #   Comment CRUD endpoints
    ├── images.py            #   Image upload to Cloudinary (+ mock mode)
    └── users.py             #   User profile, stats, leaderboard
```

### File-by-File Breakdown

#### Core Files

| File | Purpose |
|------|---------|
| **`main.py`** | Creates the FastAPI app with lifespan events (auto-creates DB tables on startup). Registers all routers, configures CORS (allow all for mobile dev), and runs uvicorn on port `8080`. |
| **`database.py`** | Reads `DATABASE_URL` from `.env`, auto-detects SQLite vs PostgreSQL, replaces sync drivers with async ones (`aiosqlite` / `asyncpg`). Configures SSL for remote Postgres. Exports `engine`, `Base`, `get_db()` dependency. |
| **`models.py`** | Defines `Post`, `Comment`, `Like` SQLAlchemy models. Posts use a 3-phase status lifecycle (`OPEN` → `IN_PROGRESS` → `PENDING_APPROVAL` → `COMPLETED`). Relationships link to `User` model in the auth module. |
| **`schemas.py`** | Pydantic v2 schemas with `from_attributes = True`. Defines `UserPublic` (safe, no email), `User` (full), `Post`, `PostCreate`, `PostUpdate`, `Comment`, `CommentCreate`, `Like`. |
| **`crud.py`** | Shared database operations: `get_user`, `get_user_by_email`, `get_user_by_username`, `get_post`, `create_comment`, `get_comments_by_post`. Uses `selectinload` for eager relationship loading. |

#### Auth Module (`auth/`)

| File | Purpose |
|------|---------|
| **`models.py`** | `User` (id, email, username, password_hash, is_banned, points), `RefreshToken` (hashed token storage with revocation), `OAuthAccount` (provider linking for GitHub/OIDC). Uses String UUIDs for SQLite+Postgres portability. |
| **`schemas.py`** | `RegisterRequest`, `LoginRequest`, `RefreshRequest`, `LogoutRequest`, `FirebaseAuthRequest` (for OAuth), `TokenResponse`, `UserResponse`, `MessageResponse`. |
| **`dependencies.py`** | `get_current_user()` — FastAPI dependency that extracts the JWT Bearer token, decodes it, fetches the user from DB, and checks ban status. Returns `User` object or raises `401`/`403`. |
| **`redis_client.py`** | Initializes Upstash Redis client using env vars. Used for fast refresh token lookups (microsecond latency vs DB round-trip). |
| **`routers/auth.py`** | **Register:** validates uniqueness (email + username), bcrypt hashes password. **Login:** verifies credentials, issues JWT access token (15min) + random refresh token (30 days), stores hash in DB + Redis. **Refresh:** checks Redis first (fast path), rotates tokens (old revoked, new issued). **Logout:** deletes from Redis instantly, marks revoked in DB for audit. **`/me`:** returns current user via JWT guard. |
| **`routers/oauth.py`** | **GitHub OAuth** via Supabase: receives Supabase JWT, verifies it, links/creates user + OAuthAccount, issues app tokens. |
| **`utils/jwt.py`** | `create_access_token()` — JWT with `sub` (user_id), `exp`, `type`. `decode_access_token()` — validates JWT. `create_refresh_token()` — `secrets.token_urlsafe(64)` (NOT a JWT). `hash_refresh_token()` — SHA-256 hash (never store raw). |
| **`utils/hashing.py`** | `hash_password()` / `verify_password()` using bcrypt. |
| **`utils/oauth_verify.py`** | `verify_supabase_token()` — decodes Supabase JWT using the Supabase JWT secret, extracts email, provider, and provider_user_id. |

#### Feature Routers (`routers/`)

| File | Purpose |
|------|---------|
| **`posts.py`** | Full post lifecycle: **Create** (with background ML classification), **Get Feed** (non-completed, paginated), **Patch** (author-only, only if OPEN), **Start Work** (volunteer clock-in), **Submit Proof** (clock-out with duration calc), **Approve** (author awards points to volunteer). All write endpoints re-fetch with `selectinload` for complete response. |
| **`post_service.py`** | Business logic layer: `get_feed()` (query builder with eager loading), `start_work()` (state transition + timestamp). Separates DB logic from HTTP concerns. |
| **`ml_service.py`** | Background tasks: `process_post_ml()` sends image URL to classifier, updates post with predicted class + points. `verify_volunteer_post_ml()` verifies "before" photo validity. Uses `AsyncSessionLocal` for independent DB sessions in background tasks. |
| **`comments.py`** | **Create comment** (auth required, verifies post exists), **List comments** (public, by post_id). |
| **`images.py`** | **Upload image** (auth required): validates MIME type, resizes with Pillow (max 1920x1080), converts to WebP (quality 85), uploads to Cloudinary. **Mock mode** (`USE_MOCK_CLOUD=True`): returns fake URL for local testing. |
| **`users.py`** | **`/users/me`** — full profile (private). **`/users/profile/stats`** — dashboard data (task counts, points, my_requests, my_contributions). **`/users/leaderboard`** — top 10 users by points (public). |

---

## Setup Guide

### Prerequisites

- **Python 3.12+**
- **pip** (comes with Python)
- A virtual environment (recommended)

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/volunteer-cleanup-network.git
cd volunteer-cleanup-network/backend
```

### 2. Create & Activate Virtual Environment

```bash
# Windows
python -m venv venv
.\venv\Scripts\activate

# macOS/Linux
python3 -m venv venv
source venv/bin/activate
```

Or use an existing environment:

### 3. Install Dependeqncies

```bash
pip install -r requirements.txt
```

**Key dependencies:**
| Package | Purpose |
|---------|---------|
| `fastapi` | Web framework |
| `uvicorn[standard]` | ASGI server |
| `sqlalchemy[asyncio]` | Async ORM |
| `aiosqlite` | Async SQLite driver |
| `asyncpg` | Async PostgreSQL driver |
| `python-jose[cryptography]` | JWT encoding/decoding |
| `bcrypt` | Password hashing |
| `passlib` | Password utility |
| `python-dotenv` | `.env` file loading |
| `httpx` | Async HTTP client (for ML service) |
| `cloudinary` | Image cloud storage |
| `Pillow` | Image processing |
| `upstash-redis` | Serverless Redis client |
| `pydantic[email]` | Data validation with email support |

### 4. Configure Environment Variables

Create a `.env` file in the `backend/` directory:

```env
# --- Database ---
# For local development (SQLite):
DATABASE_URL=sqlite:///./auth.db

# For production (PostgreSQL):
# DATABASE_URL=postgresql://user:password@host:port/dbname

# --- JWT Auth ---
JWT_SECRET=your-secret-key-change-this
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30

# --- Supabase OAuth (GitHub login) ---
SUPABASE_JWT_SECRET=your-supabase-jwt-secret
SUPABASE_URL=https://your-project.supabase.co

# --- Upstash Redis ---
UPSTASH_REDIS_URL=https://your-redis.upstash.io
UPSTASH_REDIS_TOKEN=your-redis-token

# --- Cloudinary (Image uploads) ---
CLOUDINARY_CLOUD_NAME=your-cloud-name
CLOUDINARY_API_KEY=your-api-key
CLOUDINARY_API_SECRET=your-api-secret

# --- ML Classifier Microservice ---
CLASSIFIER_MICORSERVICE=http://localhost:6969

# --- Dev Toggles ---
# Set to "True" to use mock image uploads (no Cloudinary calls)
USE_MOCK_CLOUD=True
```

### 5. Run the Server

```bash
python main.py
```

The server starts on `http://0.0.0.0:8080` with auto-reload.

- **Swagger UI:** [http://127.0.0.1:8080/docs](http://127.0.0.1:8080/docs)
- **ReDoc:** [http://127.0.0.1:8080/redoc](http://127.0.0.1:8080/redoc)

On first run, all database tables are auto-created via the lifespan event.




## API Endpoints

### Health Check

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/` | No | Health check — returns `{"message": "App API is running"}` |

### Authentication (`/auth`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/auth/register` | No | Register a new user (email, username, password) |
| `POST` | `/auth/login` | No | Login — returns access + refresh tokens |
| `POST` | `/auth/refresh` | No | Rotate refresh token, get new access token |
| `POST` | `/auth/logout` | No | Invalidate refresh token (Redis + DB) |
| `GET` | `/auth/me` | Yes | Get current user profile from JWT |

### OAuth (`/oauth`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/oauth/github` | No | GitHub login via Supabase JWT token |

### Users (`/users`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/users/me` | Yes | Full user profile (private, includes email) |
| `GET` | `/users/profile/stats` | Yes | Dashboard: counts, requests, contributions |
| `GET` | `/users/leaderboard` | No | Top 10 users by points (public) |

### Posts (`/posts`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/posts/` | No | Get feed (non-completed posts, paginated) |
| `POST` | `/posts/` | Yes | Create cleanup request (triggers ML in background) |
| `PATCH` | `/posts/{id}` | Yes | Author updates post (class, points, caption) |
| `POST` | `/posts/{id}/start_work` | Yes | Volunteer clocks in (before photo required) |
| `POST` | `/posts/{id}/submit_proof` | Yes | Volunteer clocks out (after photo required) |
| `POST` | `/posts/{id}/approve` | Yes | Author approves & awards points to volunteer |

### Comments (`/comments`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/comments/?post_id={id}` | Yes | Add comment to a post |
| `GET` | `/comments/?post_id={id}` | No | List comments for a post |

### Images (`/images`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/images/upload/` | Yes | Upload image (resized → WebP → Cloudinary) |

---

## Authentication System

The auth system uses a **dual-token strategy** with Redis caching:

```
┌──────────┐                   ┌──────────┐
│  Client  │── Login ────────> │  Server  │
│ (Flutter)│<── access_token ──│          │
│          │    refresh_token  │          │
└────┬─────┘                   └────┬─────┘
     │                              │
     │  API calls with              │  Stores refresh_token hash in:
     │  Authorization: Bearer JWT   │   - Redis (fast lookup, TTL)
     │                              │   - PostgreSQL (audit trail)
     │                              │
     │  When access expires (15m):  │
     │  POST /auth/refresh          │  Checks Redis → rotates tokens
     └──────────────────────────────┘
```

### Token Details

| Token | Type | Lifetime | Storage |
|-------|------|----------|---------|
| **Access Token** | JWT (`HS256`) | 15 minutes | Client only (never stored server-side) |
| **Refresh Token** | Random string (`secrets.token_urlsafe(64)`) | 30 days | Client holds raw token; server stores SHA-256 **hash** in Redis + DB |

### Security Features

- **Password hashing:** bcrypt with auto-salt
- **Refresh token rotation:** on every refresh, old token is revoked and new one issued
- **Redis-first validation:** refresh token lookup is O(1) via Redis, not a DB query
- **Instant logout:** Redis key deleted immediately; DB marked for audit trail
- **Ban enforcement:** checked on every authenticated request via `get_current_user`
- **Token hash storage:** raw refresh tokens never stored in DB — only SHA-256 hashes

---

## Database Models

### Entity Relationship

```
┌──────────┐       ┌──────────────┐
│   User   │──1:N──│    Post      │ (as author)
│          │──1:N──│              │ (as volunteer)
│          │──1:N──│              │ (as resolved_by)
│          │       └──────┬───────┘
│          │              │
│          │──1:N──┌──────┴───────┐
│          │       │   Comment    │
│          │       └──────────────┘
│          │──1:N──┌──────────────┐
│          │       │     Like     │
│          │       └──────────────┘
│          │──1:N──┌──────────────┐
│          │       │ RefreshToken │
│          │       └──────────────┘
│          │──1:N──┌──────────────┐
│          │       │ OAuthAccount │
└──────────┘       └──────────────┘
```

### Post Status Lifecycle

```
  OPEN ──> IN_PROGRESS ──> PENDING_APPROVAL ──> COMPLETED
   │                                              
   └────────────────> CANCELLED                  
```

---

## Volunteer Workflow

The core gamification loop follows a **3-phase task lifecycle**:

### Phase 1 — Author Reports Waste
1. Author uploads a photo via `/images/upload/`
2. Author creates a post via `POST /posts/` with image URL + GPS coords
3. Background task sends image to ML classifier for auto-classification
4. Post status: **`OPEN`**

### Phase 2 — Volunteer Clocks In
1. Volunteer calls `POST /posts/{id}/start_work` with a "before" photo
2. Post status changes to **`IN_PROGRESS`**
3. Background task runs ML verification on the volunteer's photo
4. Timestamp recorded for duration tracking

### Phase 3 — Volunteer Clocks Out & Author Approves
1. Volunteer calls `POST /posts/{id}/submit_proof` with an "after" photo
2. Post status changes to **`PENDING_APPROVAL`**
3. Cleanup duration is calculated automatically
4. Author reviews proof and calls `POST /posts/{id}/approve` with final points
5. Points are awarded to volunteer's account
6. Post status: **`COMPLETED`**

---

## External Services

| Service | Purpose | Required? |
|---------|---------|-----------|
| **Upstash Redis** | Refresh token caching, instant logout | Yes (for auth refresh/logout) |
| **Cloudinary** | Image upload & CDN | Yes for production; mock mode available |
| **ML Classifier** | Trash type classification from images | No (runs in background, fails gracefully) |
| **Supabase** | GitHub OAuth provider | Only for OAuth login flow |

---

## Docker Deployment

### Build & Run

```bash
docker build -t cleanup-backend .
docker run -p 8080:8080 --env-file .env cleanup-backend
```

### Dockerfile Summary

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port $PORT --reload"]
```

> **Note:** The `$PORT` variable allows cloud providers (Railway, Render, etc.) to inject their own port.

---

## API Test Results

All core endpoints have been tested and verified:

```
HEALTH CHECK .......................... [PASS]
AUTH: Register (new user) ............. [PASS]
AUTH: Register (duplicate email) ...... [PASS] (400)
AUTH: Register (duplicate username) ... [PASS] (400)
AUTH: Login (valid) ................... [PASS]
AUTH: Login (wrong password) .......... [PASS] (401)
AUTH: Login (nonexistent email) ....... [PASS] (401)
AUTH: /me (valid token) ............... [PASS]
AUTH: /me (no token) .................. [PASS] (401)
AUTH: /me (invalid token) ............. [PASS] (401)
AUTH: Refresh (valid) ................. [PASS]
AUTH: Refresh (invalid) ............... [PASS] (401)
AUTH: Refresh (post-refresh works) .... [PASS]
USERS: /me ............................ [PASS]
USERS: /profile/stats ................. [PASS]
USERS: /leaderboard ................... [PASS]
POSTS: Create ......................... [PASS] (201)
POSTS: Feed ........................... [PASS]
POSTS: Patch (author update) .......... [PASS]
VOLUNTEER: Clock In ................... [PASS]
VOLUNTEER: Clock Out .................. [PASS]
VOLUNTEER: Author Approve ............. [PASS]
COMMENTS: Create ...................... [PASS]
COMMENTS: List ........................ [PASS]
IMAGES: Upload (mock) ................. [PASS]
AUTHZ: Non-author edit blocked ........ [PASS] (403)
AUTH: Logout .......................... [PASS]
AUTH: Post-logout refresh blocked ..... [PASS] (401)
```


