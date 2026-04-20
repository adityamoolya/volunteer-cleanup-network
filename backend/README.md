# Volunteer Cleanup Network -- Backend

A **FastAPI** backend powering a community-driven trash cleanup platform. Users report waste sightings, volunteers claim and clean them up, and the system awards points -- creating a gamified environmental cleanup loop.

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
- [Production Deployment (AWS EC2)](#production-deployment-aws-ec2)
- [Security Hardening](#security-hardening)

---

## Architecture Overview

```
+--------------+     +--------------+     +------------------+
|  Flutter App |---->|   FastAPI     |---->|  SQLite / PgSQL  |
|  (Frontend)  |<----|   Backend     |<----|  (Database)      |
+--------------+     +------+-------+     +------------------+
                            |
              +-------------+-------------+
              |             |             |
        +-----+-----+ +----+----+ +------+------+
        | Cloudinary | |  Redis  | | ML Service  |
        | (Images)   | |(Upstash)| |(Classifier) |
        +-----------+ +---------+ +-------------+
```

**Tech Stack:**
- **Framework:** FastAPI (async, Python 3.12)
- **ORM:** SQLAlchemy 2.0 (async with `asyncpg` / `aiosqlite`)
- **Auth:** JWT (access tokens) + hashed refresh tokens + Redis cache
- **Image Storage:** Cloudinary (with mock mode for local dev)
- **ML Service:** External trash classifier microservice (ONNX, runs in sibling container)
- **Cache/Session:** Upstash Redis (serverless)
- **Database:** SQLite (local dev) / PostgreSQL (production)
- **Notifications:** Firebase Cloud Messaging (FCM) via Firebase Admin SDK

For authentication internals, refer to the [Auth Module README](./auth/README.md).

---

## Project Structure

```
backend/
├── main.py                  # Application entry point & FastAPI app factory
├── database.py              # Async SQLAlchemy engine, session factory, DB config
├── models.py                # SQLAlchemy models: Post, Comment, Like, Reward, RedemptionRequest
├── schemas.py               # Pydantic schemas for request/response validation
├── crud.py                  # Reusable CRUD operations (users, posts, comments)
├── .env                     # Environment variables (secrets, DB URL, API keys)
├── requirements.txt         # Python dependencies
├── Dockerfile               # Container build instructions
├── auth.db                  # SQLite database file (auto-created, gitignored)
│
├── auth/                    # -- Authentication Module (see auth/README.md) ----
│   ├── __init__.py
│   ├── models.py            #   User, RefreshToken, OAuthAccount, Admin models
│   ├── schemas.py           #   Auth request/response Pydantic schemas
│   ├── dependencies.py      #   get_current_user dependency (JWT guard)
│   ├── redis_client.py      #   Upstash Redis client for refresh token cache
│   ├── README.md            #   Auth module setup documentation
│   │
│   ├── routers/             #   -- Auth API Routes --
│   │   ├── __init__.py
│   │   ├── auth.py          #     Register, Login, Refresh, Logout, /me
│   │   └── oauth.py         #     GitHub OAuth via Supabase JWT
│   │
│   └── utils/               #   -- Auth Utilities --
│       ├── __init__.py
│       ├── jwt.py           #     JWT creation, decoding, refresh token hashing
│       ├── hashing.py       #     bcrypt password hashing & verification
│       └── oauth_verify.py  #     Supabase/GitHub token verification
│
└── routers/                 # -- Feature Routes ----------------------------
    ├── __init__.py
    ├── posts.py             #   Post CRUD + volunteer workflow endpoints
    ├── post_service.py      #   Business logic: feed queries, start_work
    ├── ml_service.py        #   Background tasks: ML classification calls
    ├── comments.py          #   Comment CRUD endpoints
    ├── images.py            #   Image upload to Cloudinary (+ mock mode)
    ├── users.py             #   User profile, stats, leaderboard
    ├── admins.py            #   Admin-only routes (ban, promote, reward mgmt)
    ├── rewards.py           #   Reward catalog and redemption requests
    └── notification_service.py  # Firebase push notification helper
```

### File-by-File Breakdown

#### Core Files

| File | Purpose |
|------|---------|
| **`main.py`** | Creates the FastAPI app with lifespan events (auto-creates DB tables on startup). Registers all routers, configures CORS (allow all for mobile dev), and runs uvicorn on port `8080`. |
| **`database.py`** | Reads `DATABASE_URL` from `.env`, auto-detects SQLite vs PostgreSQL, replaces sync drivers with async ones (`aiosqlite` / `asyncpg`). Configures SSL for remote Postgres. Exports `engine`, `Base`, `get_db()` dependency. |
| **`models.py`** | Defines `Post`, `Comment`, `Like`, `Reward`, `RedemptionRequest` SQLAlchemy models. Posts use a multi-phase status lifecycle (`OPEN` -> `IN_PROGRESS` -> `PENDING_APPROVAL` -> `COMPLETED`). Relationships link to `User` model in the auth module. |
| **`schemas.py`** | Pydantic v2 schemas with `from_attributes = True`. Defines `UserPublic` (safe, no email), `User` (full), `Post`, `PostCreate`, `PostUpdate`, `Comment`, `CommentCreate`, `Like`, `Reward`, `RedemptionRequestItem`, admin schemas. |
| **`crud.py`** | Shared database operations: `get_user`, `get_user_by_email`, `get_user_by_username`, `get_post`, `create_comment`, `get_comments_by_post`. Uses `selectinload` for eager relationship loading. |

#### Auth Module (`auth/`)

Documented separately. See [auth/README.md](./auth/README.md) for token lifecycle, OAuth setup, Redis caching, and provider swapping details.

#### Feature Routers (`routers/`)

| File | Purpose |
|------|---------|
| **`posts.py`** | Full post lifecycle: **Create** (with background ML classification), **Get Feed** (non-completed, paginated), **Patch** (author-only, only if OPEN), **Start Work** (volunteer clock-in), **Submit Proof** (clock-out with duration calc), **Approve** (author awards points to volunteer). All write endpoints re-fetch with `selectinload` for complete response. |
| **`post_service.py`** | Business logic layer: `get_feed()` (query builder with eager loading), `start_work()` (state transition + timestamp). Separates DB logic from HTTP concerns. |
| **`ml_service.py`** | Background tasks: `process_post_ml()` sends image URL to classifier, updates post with predicted class + points. `verify_volunteer_post_ml()` verifies "before" photo validity. Uses `AsyncSessionLocal` for independent DB sessions in background tasks. |
| **`comments.py`** | **Create comment** (auth required, verifies post exists), **List comments** (public, by post_id). |
| **`images.py`** | **Upload image** (auth required): validates MIME type, resizes with Pillow (max 1920x1080), converts to WebP (quality 85), uploads to Cloudinary. **Mock mode** (`USE_MOCK_CLOUD=True`): returns fake URL for local testing. |
| **`users.py`** | **`/users/me`** -- full profile (private). **`/users/profile/stats`** -- dashboard data (task counts, points, my_requests, my_contributions). **`/users/leaderboard`** -- top 10 users by points (public). Point appeal/redemption requests via profile. |
| **`admins.py`** | Admin-guarded routes: remove user, promote to admin, ban/unban, search users, create rewards, restock, review redemption requests. All routes auto-require admin via router-level dependency. |
| **`rewards.py`** | User-facing reward endpoints: list available rewards (filtered by affordability and stock), request redemption (deducts points immediately). |
| **`notification_service.py`** | Firebase Admin SDK init + `send_notification()` / `notify_user_async()` helpers. Handles stale FCM token cleanup. Mock mode available via `USE_MOCK_NOTIFICATION`. |

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

### 3. Install Dependencies

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
| `firebase-admin` | Push notifications via FCM |

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

# --- Firebase (Push Notifications) ---
# Place the Firebase Admin SDK JSON in backend/ root
# USE_MOCK_NOTIFICATION=True   # set to skip real FCM calls in dev

# --- Dev Toggles ---
# Set to "True" to use mock image uploads (no Cloudinary calls)
USE_MOCK_CLOUD=True
```

### 5. Run the Server

```bash
python main.py
```

The server starts on `http://0.0.0.0:8080` with auto-reload.

- **Swagger UI:** `http://127.0.0.1:8080/docs`
- **ReDoc:** `http://127.0.0.1:8080/redoc`

On first run, all database tables are auto-created via the lifespan event.

---

## API Endpoints

### Health Check

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/` | No | Health check -- returns `{"message": "App API is running"}` |

### Authentication (`/auth`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/auth/register` | No | Register a new user (email, username, password) |
| `POST` | `/auth/login` | No | Login -- returns access + refresh tokens |
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
| `POST` | `/images/upload/` | Yes | Upload image (resized -> WebP -> Cloudinary) |

### Rewards (`/rewards`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/rewards/available` | Yes | List rewards user can afford and are in stock |
| `POST` | `/rewards/{reward_id}/request` | Yes | Request a reward redemption (points deducted) |

### Admin (`/admin`)

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `DELETE` | `/admin/remove/{user_id}` | Admin | Hard-delete a user account |
| `POST` | `/admin/promote/{user_id}` | Admin | Promote user to admin |
| `POST` | `/admin/ban/{user_id}` | Admin | Ban or unban a user |
| `GET` | `/admin/users/search` | Admin | Look up user by username or email |
| `POST` | `/admin/rewards` | Admin | Create a new reward |
| `POST` | `/admin/rewards/{reward_id}/restock` | Admin | Add stock to existing reward |
| `GET` | `/admin/rewards/requests` | Admin | View pending redemption requests |
| `POST` | `/admin/rewards/requests/{request_id}/review` | Admin | Approve or reject a redemption request |

---

## Authentication System

The auth system uses a **dual-token strategy** with Redis caching.

Refer to [auth/README.md](./auth/README.md) for the full breakdown including token lifecycle diagrams, OAuth flow, provider swapping, and local-vs-production checklists.

### Token Summary

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
- **Token hash storage:** raw refresh tokens never stored in DB -- only SHA-256 hashes

---

## Database Models

### Entity Relationship

```
+----------+       +--------------+
|   User   |--1:N--| Post         | (as author)
|          |--1:N--|              | (as volunteer)
|          |--1:N--|              | (as resolved_by)
|          |       +------+-------+
|          |              |
|          |--1:N--+------+-------+
|          |       |   Comment    |
|          |       +--------------+
|          |--1:N--+--------------+
|          |       |     Like     |
|          |       +--------------+
|          |--1:N--+--------------+
|          |       | RefreshToken |
|          |       +--------------+
|          |--1:N--+--------------+
|          |       | OAuthAccount |
|          |       +--------------+
|          |--1:N--+--------------+
|          |       | Redemption   |
|          |       | Request      |
+----------+       +--------------+
     |
     +--1:1--+--------------+
             |    Admin      |
             +--------------+

+--------------+
|   Reward     |--1:N-- RedemptionRequest
+--------------+
```

### Post Status Lifecycle

```
  OPEN --> IN_PROGRESS --> PENDING_APPROVAL --> COMPLETED
   |
   +----------------> CANCELLED
```

---

## Volunteer Workflow

The core gamification loop follows a **3-phase task lifecycle**:

### Phase 1 -- Author Reports Waste
1. Author uploads a photo via `/images/upload/`
2. Author creates a post via `POST /posts/` with image URL + GPS coords
3. Background task sends image to ML classifier for auto-classification
4. Post status: **`OPEN`**

### Phase 2 -- Volunteer Clocks In
1. Volunteer calls `POST /posts/{id}/start_work` with a "before" photo
2. Post status changes to **`IN_PROGRESS`**
3. Background task runs ML verification on the volunteer's photo
4. Timestamp recorded for duration tracking

### Phase 3 -- Volunteer Clocks Out & Author Approves
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
| **Firebase** | Push notifications (FCM) | Yes for production; mock mode available |

---

## Docker Deployment

The project ships with a `docker-compose.yml` at the repo root that orchestrates both the backend and ML classifier as sibling containers on a shared bridge network.

### Docker Compose Overview

```yaml
services:
  backend:
    build: ./backend
    container_name: vcn_backend
    restart: always
    ports:
      - "8080:8080"
    env_file:
      - ./backend/.env

  ml:
    build: ./trash_classifier
    container_name: vcn_ml
    restart: always
    ports:
      - "6969:6969"
```

Both services share a `vcn_network` bridge. The backend reaches the classifier at `http://vcn_ml:6969` using Docker's internal DNS.

### Dockerfile Summary

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Build & Run (Local)

```bash
docker compose up --build -d
```

---

## Production Deployment (AWS EC2)

The backend and ML service run on an AWS EC2 instance behind nginx, with HTTPS via Let's Encrypt and a free DuckDNS subdomain. No CLI commands below -- just the sequence of steps.

### 1. Provision the EC2 Instance

- Launch an Ubuntu instance (t2.micro or t3.small depending on ML model memory needs).
- During launch, create or attach a security group that opens inbound ports **22** (SSH), **80** (HTTP), **443** (HTTPS). Port 8080 and 6969 should stay closed to the public -- nginx proxies to them internally.
- Download the SSH key pair and connect via your terminal.

### 2. Install Docker and Docker Compose

- Install Docker Engine from the official Docker apt repository (not the snap or distro-default version).
- Install the Docker Compose plugin (comes bundled with modern Docker Engine installs).
- Add your user to the `docker` group so you do not need sudo for every command.

### 3. Clone the Repository and Configure

- Clone this repo onto the instance.
- Copy or create the `backend/.env` file with production values (PostgreSQL URL, real Cloudinary keys, real Redis credentials, a strong JWT secret).
- Place the Firebase Admin SDK JSON file in the `backend/` directory (the filename must match what `notification_service.py` expects).
- Set `CLASSIFIER_MICORSERVICE=http://vcn_ml:6969` in `.env` so the backend uses Docker internal networking to reach the ML container.

### 4. Start Containers

- From the repo root, run docker compose in detached mode.
- Verify both containers are healthy and the backend responds on `localhost:8080`.

### 5. Get a DuckDNS Subdomain

- Register at duckdns.org and create a subdomain (e.g. `yourproject.duckdns.org`).
- Point it to your EC2 instance's public IP.
- Optionally set up a cron job or systemd timer on the instance to periodically update the DuckDNS record if the IP changes (relevant for non-Elastic-IP setups).

### 6. Install and Configure Nginx

- Install nginx from the system package manager.
- Create a server block that listens on port 80, sets `server_name` to your DuckDNS domain, and proxies all traffic to `http://127.0.0.1:8080`.
- Make sure to pass `Host`, `X-Real-IP`, and `X-Forwarded-For` headers through the proxy so the backend sees real client IPs.
- Test the config and reload nginx.

### 7. HTTPS via Certbot

- Install certbot and the nginx plugin from the system package manager.
- Run certbot with the nginx plugin for your DuckDNS domain.
- Certbot will automatically modify the nginx config to listen on 443 with the certificate and redirect port 80 to 443.
- Certbot auto-renews via a systemd timer; verify the timer is active.

### 8. Verify

- Hit `https://yourproject.duckdns.org/` from a browser or curl -- it should return the health check JSON over HTTPS.
- Update the Flutter app's `.env` to point `BACKEND_API` to `https://yourproject.duckdns.org`.

---

## Security Hardening

### Nginx Rate Limiting

Configure rate limiting in the nginx `http` block to prevent abuse. Define a rate limit zone keyed by client IP and apply it to the server or specific locations. A reasonable starting point is 10 requests per second with a short burst allowance. Auth endpoints (`/auth/login`, `/auth/register`) should have a stricter limit (e.g. 3 requests per second) to slow down brute-force attempts.

### Blocking /docs and /redoc in Production

The Swagger UI (`/docs`) and ReDoc (`/redoc`) endpoints expose the full API schema publicly. In production, these should not be accessible to arbitrary users.

**Option A -- Block at nginx level:** Add `location` blocks for `/docs` and `/redoc` that return 403 or require HTTP Basic Auth (username/password configured in an htpasswd file). This way the endpoints still exist for your team behind a password but are invisible to the public.

**Option B -- Disable in FastAPI:** Set `docs_url=None` and `redoc_url=None` in the `FastAPI()` constructor when running in production (controlled via an env var). This removes the routes entirely.

Currently `redoc_url` is already set to `None` in `main.py`. Apply similar treatment to `docs_url` when the admin panel is ready to manage things without Swagger.

### Admin Panel

**TODO:** The admin endpoints (`/admin/*`) currently work via API calls only (Swagger or direct HTTP). A proper admin web panel (React, or a lightweight tool like FastAPI-Admin) needs to be built to provide a UI for user management, reward CRUD, and redemption approvals. Until then, admin operations are performed through the API directly by users who have been promoted to the Admin table.

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
