from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging

from database import engine, Base
from routers import auth, posts, comments, images, users

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
    version="6.9"
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
app.include_router(auth.router, prefix="/auth") #handles authenitcation
app.include_router(users.router)    # handles users data and stats
app.include_router(posts.router)   # handles the posts router
app.include_router(comments.router) # self explainatory ig
app.include_router(images.router) #uploads images to cloudinary
#checks if api is up or not
@app.get("/", tags=["Health Check"])
def read_root():
    return {"message": "Community App API is running"}



#railway hosting???