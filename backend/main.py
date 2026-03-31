"""
    File: backend/main.py
    Description: 
        The main entry point for the FastAPI application, containing app initialization and router inclusions.
"""

'''documentaion of each file is given at the top of each file
    this is so that i dont loose track of what each file does
    

    main.py
    entry point of app,logging modules imported here , mapped to routers
'''
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging
import uvicorn
from pathlib import Path
from dotenv import load_dotenv
from database import engine, Base
#makes .env vars avaible to router files also
BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

# CONFIGURE logger
logging.basicConfig(
    level=logging.INFO, # Capture everything from INFO and above (WARNING, ERROR)
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

from auth.models import User, RefreshToken, OAuthAccount
from auth.routers import auth as auth_router, oauth as oauth_router
from routers import posts, comments, images, users

# --- Lifespan event for startup ---
@asynccontextmanager
async def lifespan(app: FastAPI):
    logging.info("Application startup...")
    async with engine.begin() as conn: #creates new databases table if not already there
        await conn.run_sync(Base.metadata.create_all)
    logging.info("Database tables created/verified.")
    yield
    logging.info("Application shutdown...")

app = FastAPI(
    lifespan=lifespan,
    title="Community Task APi",
    version="7.0"
)

# CORS configuration
origins = ["*"] # Allow all for mobile app development 

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register Routers 
app.include_router(auth_router.router, prefix="/auth", tags=["auth"])
app.include_router(oauth_router.router, prefix="/oauth", tags=["oauth"])
app.include_router(users.router)    # handles users data and stats
app.include_router(posts.router)   # handles the posts router
app.include_router(comments.router) # self explainatory ig
app.include_router(images.router) #uploads images to cloudinary


#checks if api is up or not
@app.get("/", tags=["Health Check"])
def read_root():
    return {"message": "App API is running"}

if __name__ == "__main__":
    logger.info("http://127.0.0.1:8080") #this should produce a link
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8080,
        reload=True
        
    )