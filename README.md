# CleanQuest - Community Cleanup Platform

A gamified community-driven platform for reporting environmental issues and coordinating cleanup efforts. Built with FastAPI, PostgreSQL, TensorFlow, and Flutter.

## Tech Stack

### Backend
- **FastAPI** - Async Python web framework
- **PostgreSQL** - Production database (SQLite for local development)
- **SQLAlchemy** - Async ORM with relationship loading
- **Argon2** - Password hashing
- **JWT** - Token-based authentication
- **Cloudinary** - Image hosting and optimization

### Machine Learning Service
- **TensorFlow** - Waste classification model
- **MobileNetV2** - Pre-trained CNN for image recognition
- **FastAPI** - Microservice API

### Frontend
- **Flutter** - Cross-platform mobile framework
- See [Flutter README](./flutter_code/README.md) for details

## Architecture Overview

```
CleanQuest/
├── backend/                    # Main FastAPI application
│   ├── main.py                 # Application entry point
│   ├── database.py             # Database configuration
│   ├── models.py               # SQLAlchemy models
│   ├── schemas.py              # Pydantic validation schemas
│   ├── crud.py                 # Database operations
│   ├── auth_utils.py           # JWT and password hashing
│   └── routers/                # API endpoints
│       ├── auth.py             # Authentication
│       ├── posts.py            # Task management
│       ├── users.py            # User profiles and leaderboard
│       ├── comments.py         # Task discussions
│       └── images.py           # Image upload
│
├── trash_classifier/           # ML microservice
│   ├── main.py                 # Classification API
│   ├── waste_classifier_model.h5
│   └── requirements.txt
│
└── flutter_code/               # Mobile application
    └── (See flutter_code/README.md)
```

## Overview

CleanQuest enables citizens to report environmental issues with GPS-tagged photos. Volunteers can browse open tasks on a map, claim them, and submit proof of cleanup. The platform uses machine learning to classify waste types and award points accordingly.

### Workflow

1. **Report**: Citizens photograph environmental issues with automatic GPS tagging
2. **Classify**: ML service analyzes the image and assigns category and points
3. **Volunteer**: Community members browse and claim open tasks
4. **Clock In**: Volunteers take "before" photos when arriving at the site
5. **Clock Out**: Submit "after" photos as proof of completion
6. **Approve**: Task authors review proof and award points
7. **Leaderboard**: Track community impact and top contributors

## Features

### Task Management
- Create cleanup requests with image and location
- Automatic waste classification (cardboard, glass, metal, paper, plastic, trash)
- ML-based point assignment (0-20 points based on waste type)
- Three-phase task lifecycle: OPEN → IN_PROGRESS → PENDING_APPROVAL → COMPLETED
- Background ML processing for non-blocking user experience

### Volunteer System
- Browse all open tasks with pagination
- Clock in/out system with timestamp tracking
- Before and after photo submissions
- Automatic duration calculation
- Point verification against original classification

### Gamification
- Point system tied to waste recyclability
- Global leaderboard (top 10 users) 
- Personal dashboard with task history
- Separate tracking for created vs completed tasks

### Community Features
- Task comments and discussions
- Like system for popular requests
- User profiles with public stats
- Real-time task status updates

## API Endpoints

### Authentication
- `POST /auth/register` - Create account
- `POST /auth/token` - Login (returns JWT)

### Tasks
- `GET /posts/` - List open tasks (paginated)
- `POST /posts/` - Create cleanup request
- `PATCH /posts/{id}` - Update task details (author only)
- `POST /posts/{id}/start_work` - Clock in as volunteer
- `POST /posts/{id}/submit_proof` - Clock out with completion proof
- `POST /posts/{id}/approve` - Approve and award points (author only)

### Users
- `GET /users/me` - Private profile with email
- `GET /users/profile/stats` - Dashboard with task history
- `GET /users/leaderboard` - Top 10 users by points

### Comments
- `POST /comments/?post_id={id}` - Add comment
- `GET /comments/?post_id={id}` - Get task comments

### Images
- `POST /images/upload/` - Upload to Cloudinary

### ML Service
- `POST /predict_with_urls` - Classify waste from image URL
- `POST /predict_with_file` - Classify waste from uploaded file

## Installation

### Prerequisites
- Python 3.12+
- PostgreSQL (or SQLite for local development)
- Cloudinary account
- Flutter SDK 3.0+ (for mobile app)

### Backend Setup

1. Clone and navigate to backend directory:
```bash
git clone <repository-url>
cd backend
```

2. Create virtual environment:
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

4. Configure environment variables (`.env`):
```ini
# Database
DATABASE_URL=sqlite+aiosqlite:///./local_test.db
# For production: postgresql+asyncpg://user:pass@host:port/db

# Security
SECRET_KEY=<generate-with-openssl-rand-hex-32>

# Cloudinary
CLOUDINARY_CLOUD_NAME=your_cloud_name
CLOUDINARY_API_KEY=your_api_key
CLOUDINARY_API_SECRET=your_api_secret

# ML Service URL
CLASSIFIER_MICORSERVICE=http://localhost:6969
```

5. Run the server:
```bash
uvicorn main:app --reload
```

API available at `http://127.0.0.1:8000`  
Swagger docs at `http://127.0.0.1:8000/docs`

### ML Service Setup

1. Navigate to classifier directory:
```bash
cd trash_classifier
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Ensure model file exists:
```bash
ls waste_classifier_model.h5
```

4. Run the service:
```bash
uvicorn main:app --host 0.0.0.0 --port 6969 --reload
```

Service available at `http://127.0.0.1:6969`

### Frontend Setup

See [Flutter README](./flutter_source_code/README.md) for mobile app installation and configuration.

## Deployment

### Backend (Railway/Render)

Current deployment uses an alternate account due to free tier limitations:  
**Live Backend**: [https://github.com/Devil-tech828/env-El-rvce.git](https://github.com/Devil-tech828/env-El-rvce.git)

Standard Railway deployment:
1. Create new project and link GitHub repository
2. Add PostgreSQL database service
3. Configure environment variables (SECRET_KEY, CLOUDINARY_*, CLASSIFIER_MICORSERVICE)
4. Deploy using Procfile

Alternative platforms: Heroku, gcloud , AWS EC2 ...

### ML Service Deployment

Deploy as separate service on Railway/Render with Dockerfile. Update `CLASSIFIER_MICORSERVICE` environment variable in main backend.

### Mobile App

See [Flutter README](./flutter_source_code/README.md) for APK/IPA builds and app store publishing.

## Database Schema

### Users
- `id`, `username`, `email`, `hashed_password`, `points`, `created_at`

### Posts (Tasks)
- `id`, `image_url`, `image_public_id`, `caption`, `latitude`, `longitude`
- `predicted_class`, `points`, `status` (OPEN, IN_PROGRESS, PENDING_APPROVAL, COMPLETED, CANCELLED)
- `author_id`, `volunteer_id`, `resolved_by_id`
- `start_image_url`, `end_image_url`, `proof_image_url`
- `volunteer_start_timestamp`, `volunteer_end_timestamp`, `cleanup_duration_minutes`
- `verified_points` (ML verification result)

### Comments
- `id`, `content`, `created_at`, `author_id`, `post_id`

### Likes
- `id`, `user_id`, `post_id`