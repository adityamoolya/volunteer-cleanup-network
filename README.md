# Volunteer Cleanup Network

The Volunteer Cleanup Network is an automated, community-driven environmental cleanup platform. It gamifies the process of making our communities cleaner by connecting users who discover and report trash with volunteers who step in to perform the cleanup. 

Our system heavily leverages asynchronous machine learning models to automatically categorize the reported trash, assess the severity of the mess, and estimate point rewards—delivering a streamlined, verifiable, and highly engaging user experience.

📱 [**Download the .apk from here**](https://drive.google.com/drive/folders/166HY1sx200e-gqqEXpLeeSRyy_l35O4W?usp=sharing)

---

## Technical Documentation

Because the backend features a robust API with complex machine learning verifications, asynchronous processes, and multi-actor gamified states, we have separated the backend technical documentation.

Read the **[Backend Technical Documentation (README)](./backend/README.md)** for a deep dive into:
- The FastAPI Architecture and Database models
- Machine Learning microservice integrations
- Gamified volunteer state flow (Open -> In Progress -> Pending -> Completed)
- JWT token handling, OAuth configuration, and Redis caching
- Complete API schema and endpoint mapping

---

## Project Workflow

1. **Reporting (Author)**: An author captures an image. The backend stores it in Cloudinary and triggers an asynchronous task to categorize the trash via the ML service.
2. **Discovery**: Open tasks are displayed on the mobile feed for volunteers to view.
3. **Clock-In (Volunteer)**: GPS data verifies the volunteer is at the site. The volunteer submits a "before" photo, the server records the start time, and a second ML check verifies the trash state.
4. **Clock-Out (Volunteer)**: After cleaning, the volunteer submits a proof photo. The backend calculates cleanup duration and updates the status to pending approval.
5. **Resolution (Author)**: The author reviews the evidence bundle and approves the point payout, closing the case and awarding the volunteer.
6. **Redemption**: Volunteers can browse the reward catalog and redeem the points they earned for various rewards.

## High-Level Architecture 

- **Frontend (Mobile)**: Flutter, Dart, Dio, Geolocator.
- **Backend (API)**: FastAPI, SQLAlchemy (Async), PostgreSQL/SQLite, Upstash Redis.
- **AI Microservice**: TensorFlow / Keras models running as an independent HTTP service.
- **Infrastructure**: Hugging Face Spaces (Backend/ML hosting), Cloudinary (Images), Railway (Database).

## Live Servies

* **BACKEND_URL**: [https://adityamoolya-envirorment-el.hf.space](https://adityamoolya-envirorment-el.hf.space)
* **ML_SERVICE_URL**: [https://adityamoolya-env-ml.hf.space](https://adityamoolya-env-ml.hf.space)
