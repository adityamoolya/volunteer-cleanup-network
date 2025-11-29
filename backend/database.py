# backend/database.py

import os
import logging
import ssl
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    logger.critical("DATABASE_URL not found. Please check your .env file.")
    raise ValueError("No DATABASE_URL found.")

# --- FIX: SSL CONFIGURATION ---
connect_args = {}

# If we are connecting to a remote Postgres (like Railway), we usually need SSL.
# We check if the URL contains "postgresql" to apply this fix.
if "postgresql" in DATABASE_URL:
    # Create a flexible SSL context that accepts self-signed certificates
    # (Common requirement for many cloud database providers)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    connect_args["ssl"] = ctx

# Create the engine with the SSL args
engine = create_async_engine(
    DATABASE_URL,
    connect_args=connect_args,
    echo=False # Set to True if you want to see SQL queries in logs
)
# ------------------------------

AsyncSessionLocal = sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

Base = declarative_base()

async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        except Exception as e:
            logger.error(f"Database session error: {e}")
            await session.rollback()
            raise
        finally:
            await session.close()