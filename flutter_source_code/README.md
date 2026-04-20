# Volunteer Cleanup Network -- Flutter App

The mobile client for the Volunteer Cleanup Network platform. Built with Flutter and Dart, targeting Android. Provides the full user experience: authentication, reporting trash sightings, volunteering for cleanups, tracking points, and redeeming rewards.

---

## Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Setup Guide](#setup-guide)
- [Environment Configuration](#environment-configuration)
- [Architecture Notes](#architecture-notes)
- [Screens](#screens)

---

## Features

- **Email/password registration and login** with JWT-based session management
- **GitHub OAuth** via Supabase (one-tap sign-in)
- **Live feed** of open cleanup tasks with pull-to-refresh and pagination
- **Post creation** with camera/gallery image upload and GPS tagging
- **Volunteer workflow** -- clock in at a site (before photo), clock out (after photo), await author approval
- **Author approval flow** -- review volunteer evidence, award points
- **Comments** on posts
- **Leaderboard** -- top volunteers ranked by points
- **Profile dashboard** -- stats (tasks created, contributed, points), edit profile, FCM token for push notifications
- **Reward catalog** -- browse available rewards, request redemption
- **Point appeal** -- request review of point awards from profile
- **Push notifications** via Firebase Cloud Messaging
- **Auto token refresh** -- Dio interceptor handles 401s transparently, force-logout on unrecoverable auth failure
- **Custom backend URL** -- configurable from profile for dev/testing (stored in secure storage)

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Framework** | Flutter (Dart, SDK ^3.9.2) |
| **HTTP Client** | Dio 5.x with interceptors |
| **Auth Storage** | flutter_secure_storage (keychain/keystore) |
| **OAuth** | Supabase Flutter SDK |
| **Maps** | Google Maps Flutter |
| **Location** | Geolocator |
| **Camera** | image_picker |
| **State** | Provider |
| **Notifications** | Firebase Messaging |
| **Typography** | Google Fonts (Inter) |
| **Image Caching** | cached_network_image |
| **Theming** | Material 3, dark mode, custom color palette |

---

## Project Structure

```
flutter_source_code/
├── lib/
│   ├── main.dart                    # App entry, theme, Firebase init, Supabase init
│   │
│   ├── models/
│   │   ├── post_model.dart          # Post, status enum, author/volunteer fields
│   │   ├── profile_model.dart       # User profile data model
│   │   └── reward_model.dart        # Reward and RedemptionRequest models
│   │
│   ├── screens/
│   │   ├── splash_screen.dart       # Startup: checks stored tokens, routes accordingly
│   │   ├── auth_screen.dart         # Login / Register / GitHub OAuth UI
│   │   ├── home_scaffold.dart       # Bottom nav shell (Feed, Missions, Create, Leaderboard, Profile)
│   │   ├── feed_screen.dart         # Scrollable feed of open tasks
│   │   ├── create_post_screen.dart  # Image capture + location + post creation
│   │   ├── post_detail_screen.dart  # Full post view, volunteer actions, author approval
│   │   ├── mission_screen.dart      # User's active/completed missions
│   │   ├── leaderboard_screen.dart  # Top volunteers by points
│   │   └── profile_screen.dart      # Stats, settings, reward catalog, point appeals
│   │
│   ├── services/
│   │   ├── auth_service.dart        # Login, register, refresh, logout, token storage
│   │   ├── auth_interceptor.dart    # Dio interceptor: auto-refresh on 401, force-logout stream
│   │   ├── feed_service.dart        # Posts CRUD, volunteer actions, comments, image upload
│   │   ├── user_service.dart        # Profile fetch, stats, leaderboard, FCM token update
│   │   ├── reward_service.dart      # Reward listing and redemption requests
│   │   └── startup_service.dart     # Token validation + silent refresh on cold start
│   │
│   └── widgets/
│       ├── contribute_dialog.dart       # Clock-in dialog (before photo, GPS check)
│       └── complete_cleanup_dialog.dart # Clock-out dialog (after photo, submit proof)
│
├── assets/                          # App icon and static assets
├── android/                         # Android platform config (google-services.json goes here)
├── pubspec.yaml                     # Dependencies and asset declarations
└── .env                             # Runtime config (backend URL)
```

---

## Setup Guide

### Prerequisites

- Flutter SDK (^3.9.2)
- Android Studio or VS Code with Flutter/Dart plugins
- An Android emulator or physical device
- A Google Maps API key (for the map features)
- Firebase project with `google-services.json` configured

### 1. Clone and Enter

```bash
git clone https://github.com/your-username/volunteer-cleanup-network.git
cd volunteer-cleanup-network/flutter_source_code
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Configure Environment

Create or edit `.env` in the `flutter_source_code/` directory:

```env
BACKEND_API='https://yourproject.duckdns.org'
```

For local backend development (with emulator):

```env
BACKEND_API='http://10.0.2.2:8080'
```

### 4. Firebase Setup

- Place `google-services.json` in `android/app/`.
- The file is gitignored -- each developer needs their own copy from the Firebase console.

### 5. Run

```bash
flutter run
```

---

## Environment Configuration

| Variable | Description |
|----------|-------------|
| `BACKEND_API` | Base URL of the FastAPI backend. Points to the production EC2 instance by default. Switch to `http://10.0.2.2:8080` for local emulator development. |

The app also supports a **custom backend URL** configured at runtime from the profile screen. This value is persisted in secure storage and takes precedence over the `.env` value when set. Useful for testing against staging or local instances without rebuilding.

---

## Architecture Notes

### Auth Flow

1. On cold start, `SplashScreen` calls `StartupService` to check for stored tokens in secure storage.
2. If a valid access token exists, the app navigates to the home screen. If expired, a silent refresh is attempted.
3. If no tokens or refresh fails, the user is sent to `AuthScreen`.
4. `AuthInterceptor` (Dio interceptor) watches all API responses. On a 401, it attempts one token refresh. If that also fails, it broadcasts on the force-logout stream, which `main.dart` listens to for navigation.

### Service Layer

All HTTP calls go through service classes that wrap Dio. The interceptor is attached once at initialization. Services return parsed model objects or throw -- screens handle loading/error states.

### Theme

Dark mode only. Custom `AppColors` class in `main.dart` defines the palette (emerald-based primary, GitHub-dark-inspired surfaces). All screens use Material 3 with `GoogleFonts.inter`.

---

## Screens

| Screen | Purpose |
|--------|---------|
| **Splash** | Token check, silent refresh, route decision |
| **Auth** | Login, register, GitHub OAuth tabs |
| **Feed** | Paginated list of open cleanup tasks |
| **Create Post** | Camera/gallery capture, GPS coordinates, submit to backend |
| **Post Detail** | Full task view, volunteer clock-in/out, author approval, comments |
| **Missions** | User's in-progress and completed tasks |
| **Leaderboard** | Top 10 users ranked by points |
| **Profile** | Stats dashboard, reward catalog, point appeal, settings, custom backend URL, logout |
