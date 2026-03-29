from upstash_redis import Redis
from dotenv import load_dotenv
import os

load_dotenv()

redis = Redis(
    url=os.getenv("UPSTASH_REDIS_URL"),
    token=os.getenv("UPSTASH_REDIS_TOKEN")
)