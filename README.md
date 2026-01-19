

# Volunteer Cleanup Network

The Volunteer Cleanup Network is an automated, community-driven environmental cleanup platform. It connects authors who report trash with volunteers who perform the cleanup. The system uses an asynchronous machine learning backend to categorize trash and estimate points, ensuring a verified and gamified experience.


[Download .apk from here](https://drive.google.com/drive/folders/166HY1sx200e-gqqEXpLeeSRyy_l35O4W?usp=sharing)
## Technical Stack and Frameworks

### Frontend: Mobile Application

* **Flutter**: The primary UI framework used to build the cross-platform mobile application.
* **Dart**: The programming language used for the application logic and state management.
* **Dio**: The HTTP client used for asynchronous network requests, including image uploads and state transitions.
* **Geolocator**: A package used to retrieve GPS coordinates for verifying volunteer proximity to tasks.
* **SharedPreferences**: Used to store authentication tokens locally for 30-day persistent sessions.

### Backend: Core API and Logic

* **FastAPI**: The asynchronous Python framework providing the API endpoints for task management and authentication.
* **Python**: The core language for backend logic and integration with machine learning models.
* **SQLAlchemy (Async)**: An ORM that manages relational database interactions and enforces the cleanup state machine.
* **PostgreSQL**: The relational database used for persistent storage of user profiles and cleanup posts.
* **Pydantic**: A library used to define and validate strict data contracts for API communication.

### Machine Learning Microservice

* **TensorFlow / Keras**: Deep learning libraries used to load and run the pre-trained .h5 model for trash analysis.
* **Httpx**: An asynchronous client used by the backend to communicate with the ML microservice.
* **Image Classification**: The process of analyzing photos to identify trash categories and assign points.

## Project Workflow

1. **Reporting (Author)**: An author captures an image. The backend stores it in Cloudinary and triggers an asynchronous task to categorize the trash via the ML service.
2. **Discovery**: Open tasks are displayed on the mobile feed for volunteers to view.
3. **Clock-In (Volunteer)**: GPS data verifies the volunteer is at the site. The volunteer submits a before photo, the server records the start time, and a second ML check verifies the trash state.
4. **Clock-Out (Volunteer)**: After cleaning, the volunteer submits a proof photo. The backend calculates cleanup duration and updates the status to pending approval.
5. **Resolution (Author)**: The author reviews the evidence bundle and approves the point payout, closing the case.

## Infrastructure and Deployment

* **Hugging Face Spaces**: Hosts the containerized backend and ML microservice using Docker.
* **Docker**: Packages the backend environment for consistent execution in the cloud.
* **Supervisor**: A process manager that runs both the API and ML service inside a single Docker container.
* **Cloudinary**: A cloud service used for storing and managing user-generated cleanup photos.
* **Railway**: The hosting platform for the PostgreSQL database.

## Live backend URLs

* **BACKEND_URL**: [https://adityamoolya-envirorment-el.hf.space](https://adityamoolya-envirorment-el.hf.space)
* **ML_SERVICE_URL**: [https://adityamoolya-env-ml.hf.space](https://adityamoolya-env-ml.hf.space)

## Technical Keywords

* **Geofencing**: Logic using GPS data to ensure a volunteer is physically present at a site before they can clock in.
* **JWT**: A secure standard used to authenticate users and maintain identity across API calls.
* **Asynchronous Tasks**: Background processes that run without blocking the main API response for a smoother user experience.
* **REST API**: The architectural style used for communication between the mobile app and the backend server.
