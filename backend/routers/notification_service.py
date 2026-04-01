#TODO: clean this mess
# import httpx
import logging

logger = logging.getLogger(__name__)

async def send_ntfy_notification(user_id: str, title: str, message: str):
    """
    Sends a push notification via ntfy.sh to a specific user's topic.
    Topic could be structured like: vcn_user_{user_id}
    """
    topic = f"vcn_user_{user_id}"
    url = f"https://ntfy.sh/{topic}"
    
    headers = {
        "Title": title,
        "Priority": "default",
        "Tags": "recycle,loudspeaker" # Optional emojis
    }
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(url, data=message.encode('utf-8'), headers=headers)
            response.raise_for_status()
            logger.info(f"Notification sent to {topic}")
        except Exception as e:
            logger.error(f"Failed to send notification: {e}")