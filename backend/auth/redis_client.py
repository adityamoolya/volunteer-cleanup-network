"""
    File: backend/auth/redis_client.py
    Description: 
        Manages the Redis client connection for the application.
"""

from upstash_redis import Redis
from dotenv import load_dotenv
import os

load_dotenv()

redis = Redis(
    url=os.getenv("UPSTASH_REDIS_URL"),
    token=os.getenv("UPSTASH_REDIS_TOKEN")
)