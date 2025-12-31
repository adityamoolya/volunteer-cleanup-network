# 🌍 CleanQuest - Community Cleanup Platform

A gamified community-driven platform where citizens can report environmental issues and volunteers can take action to resolve them. Built with **FastAPI backend**, **PostgreSQL database**, and **Flutter mobile frontend**—designed for speed, clarity, and real-world impact.

> **🚀 Live Deployment:** This project's backend is currently hosted on Railway. Due to free tier limitations on the main account, deployment is managed through an alternate repository. View the live backend deployment and configuration details at: **[https://github.com/Devil-tech828/env-El-rvce.git](https://github.com/Devil-tech828/env-El-rvce.git)**

---

## 📱 What Can You Do?

### For Issue Reporters
- **Report Problems:** Snap a photo of environmental issues (garbage, debris, etc.)
- **Add Location:** Automatically capture GPS coordinates for precise location
- **Track Progress:** Monitor your reported tasks through approval to completion
- **Community Impact:** See your contributions making a real difference

### For Volunteers
- **Find Tasks:** Browse all open tasks on an interactive map view
- **Take Action:** Choose tasks based on your location and availability
- **Submit Proof:** Upload before/after photos once you've completed the cleanup
- **Earn Recognition:** Gain points for verified contributions and climb the leaderboard

### Gamification & Community
- **Points System:** Earn 50 points for each verified cleanup task
- **Global Leaderboard:** Compete with other community members
- **Task Comments:** Discuss and coordinate with others on specific tasks
- **Real-time Updates:** See live status changes as tasks progress

---

## 🏗️ Architecture Overview

```
📦 Community Task Force App
├── 🔧 backend/              # FastAPI REST API
│   ├── main.py              # Application entry point
│   ├── database.py          # PostgreSQL/SQLite async connection
│   ├── models.py            # Database schema (Users, Posts, Comments)
│   ├── schemas.py           # Pydantic validation models
│   ├── crud.py              # Database operations
│   ├── auth_utils.py        # JWT auth & Argon2 hashing
│   └── routers/             # API endpoints by feature
│       ├── auth.py          # Login & registration
│       ├── posts.py         # Task lifecycle management
│       ├── users.py         # Profiles & leaderboard
│       ├── comments.py      # Task discussions
│       └── images.py        # Cloudinary integration
│
└── 📱 flutter_code/         # Flutter mobile app
    └── (See flutter_code/README.md for details)
```

---

## 🚀 Quick Start Guide

### Prerequisites

**Backend Requirements:**
- Python 3.12+
- PostgreSQL (for production) or SQLite (for local development)
- Cloudinary account (for image hosting)

**Frontend Requirements:**
- Flutter SDK 3.0+
- Dart 3.0+
- Android Studio / Xcode (for mobile development)

---

## 🔧 Backend Setup

### 1. Clone the Repository

```bash
git clone <your-repo-url>
cd backend
```

### 2. Create Virtual Environment

```bash
# Create virtual environment
python -m venv venv

# Activate it
# Windows:
venv\Scripts\activate
# macOS/Linux:
source venv/bin/activate
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Configure Environment Variables

Create a `.env` file in the `backend/` directory:

```ini
# Database Configuration
# For local development (SQLite):
DATABASE_URL=sqlite+aiosqlite:///./local_test.db

# For production (PostgreSQL):
# DATABASE_URL=postgresql+asyncpg://user:password@host:port/database

# Security
SECRET_KEY=your_very_secret_random_key_here_change_this

# Cloudinary Image Hosting
CLOUDINARY_CLOUD_NAME=your_cloud_name
CLOUDINARY_API_KEY=your_api_key
CLOUDINARY_API_SECRET=your_api_secret
```

**🔑 Important Notes:**
- Generate a secure `SECRET_KEY` using: `openssl rand -hex 32`
- Get Cloudinary credentials from: https://cloudinary.com/
- For production, use PostgreSQL instead of SQLite

### 5. Run the Backend Server

```bash
uvicorn main:app --reload
```

The API will be available at: **http://127.0.0.1:8000**

### 6. Test the API

- **Swagger UI (Interactive):** http://127.0.0.1:8000/docs
- **ReDoc (Documentation):** http://127.0.0.1:8000/redoc
- **Health Check:** http://127.0.0.1:8000/

---

## 📱 Frontend Setup

See the **[Flutter Frontend README](./flutter_code/README.md)** for detailed setup instructions, including:
- Flutter environment setup
- Dependency installation
- API endpoint configuration
- Running on emulators and physical devices
- Building for production

---

## 🔌 API Endpoints Reference

### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/auth/register` | Register new user account |
| `POST` | `/auth/token` | Login and receive JWT token |

### Tasks (Posts)
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/posts/` | Get all open tasks (paginated) |
| `POST` | `/posts/` | Create a new task/issue report |
| `POST` | `/posts/{id}/submit-proof` | Submit cleanup proof (volunteers) |
| `POST` | `/posts/{id}/approve` | Approve proof and award points (task owner) |

### Users
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/users/me` | Get current user's private profile |
| `GET` | `/users/profile/stats` | Get dashboard stats and task history |
| `GET` | `/users/leaderboard` | Get top 10 users by points |

### Comments
| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/comments/?post_id={id}` | Add comment to a task |
| `GET` | `/comments/?post_id={id}` | Get all comments for a task |

### Images
| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/images/upload/` | Upload image to Cloudinary |

---

## ☁️ Deployment

### Railway (Recommended for Backend)

> **📌 Note:** Due to Railway free tier limitations, this project's backend is currently deployed using an alternate account. You can view the live deployment details and configuration at: **[https://github.com/Devil-tech828/env-El-rvce.git](https://github.com/Devil-tech828/env-El-rvce.git)**

**Standard Railway Deployment Steps:**

1. **Create Railway Project:**
   - Sign up at [Railway.app](https://railway.app)
   - Connect your GitHub repository

2. **Add PostgreSQL Database:**
   - Click "New" → "Database" → "PostgreSQL"
   - Railway will automatically set `DATABASE_URL`

3. **Configure Backend Service:**
   - Add the backend as a new service
   - Set environment variables:
     - `SECRET_KEY`
     - `CLOUDINARY_CLOUD_NAME`
     - `CLOUDINARY_API_KEY`
     - `CLOUDINARY_API_SECRET`

4. **Deploy:**
   - Railway auto-deploys using the `Procfile`
   - Your API will be live at: `https://your-app.railway.app`

**Alternative Deployment Options:**
- **Heroku:** Similar setup with Procfile support
- **Render:** Free tier with PostgreSQL included
- **DigitalOcean App Platform:** Scalable container deployment
- **AWS EC2/Lightsail:** More control, requires manual configuration

### Flutter App Deployment

See the [Flutter README](./flutter_code/README.md) for:
- Building APK/IPA files
- Publishing to Google Play Store
- Publishing to Apple App Store

---

## 🔐 Security Features

- **Argon2 Password Hashing:** Industry-standard password security
- **JWT Authentication:** Stateless, scalable token-based auth
- **HTTPS/SSL Support:** Secure data transmission
- **CORS Configuration:** Controlled cross-origin access
- **Input Validation:** Pydantic schema validation on all endpoints

---

## 🛠️ Technology Stack

### Backend
- **FastAPI** - Modern async Python web framework
- **PostgreSQL** - Robust relational database
- **SQLAlchemy** - Async ORM with eager loading
- **Cloudinary** - Cloud-based image hosting and optimization
- **Argon2** - Password hashing algorithm
- **JWT** - JSON Web Token authentication

### Frontend
- **Flutter** - Cross-platform mobile framework
- **Dart** - Programming language
- (See flutter_code/README.md for complete list)

---

## 📊 Database Schema

### Users
- `id`, `username`, `email`, `hashed_password`
- `points` (gamification)
- `created_at`

### Posts (Tasks)
- `id`, `image_url`, `image_public_id`, `caption`
- `latitude`, `longitude` (GPS coordinates)
- `status` (open, pending, completed)
- `proof_image_url` (volunteer's submission)
- `author_id`, `resolved_by_id`

### Comments
- `id`, `content`, `created_at`
- `author_id`, `post_id`

### Likes
- `id`, `user_id`, `post_id`

---

## 🐛 Troubleshooting

### Common Backend Issues

**Database Connection Errors:**
```bash
# Check if DATABASE_URL is set correctly
echo $DATABASE_URL

# For PostgreSQL, ensure SSL context is configured
# (Already handled in database.py)
```

**Cloudinary Upload Failures:**
- Verify credentials in `.env` file
- Check image file size (max 10MB recommended)
- Ensure internet connection is stable

**Port Already in Use:**
```bash
# Change port in uvicorn command
uvicorn main:app --reload --port 8001
```

### Common Frontend Issues

See [Flutter README](./flutter_source_code/README.md) for mobile-specific troubleshooting.

---