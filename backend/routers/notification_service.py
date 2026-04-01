"""
    File: backend/notification_service.py
    Description:
        Initializes Firebase Admin SDK and exposes a simple send_notification()
        helper. Import and call it from anywhere in the app — works like a log function.

    Usage:
        from notification_service import send_notification
        send_notification(token="device_fcm_token", title="Hello", body="World")
"""

import os
import logging
import firebase_admin
from firebase_admin import credentials, messaging

logger = logging.getLogger(__name__)

# Init (runs once on first import) ---
_BASE_DIR = os.path.dirname(os.path.abspath(__file__))
_CRED_PATH = os.path.join(_BASE_DIR, "envirorment-el-firebase-adminsdk-fbsvc-9599c2dc71.json")

if not firebase_admin._apps:
    cred = credentials.Certificate(_CRED_PATH)
    firebase_admin.initialize_app(cred)
    logger.info("[FCM] Firebase Admin SDK initialized.")


# Public helper ---

def send_notification(token: str, title: str, body: str, data: dict = None) -> bool:
    """
    Send a push notification to a single device.

    Args:
        token:  FCM registration token of the target device (stored on User model).
        title:  Notification title.
        body:   Notification body text.
        data:   Optional dict of string key-value pairs for silent/data payloads.

    Returns:
        True if sent successfully, False otherwise.

    Example:
        send_notification(user.fcm_token, "Task Accepted!", "A volunteer is on the way.")
        send_notification(user.fcm_token, "Points Earned", "+50 pts", data={"type": "reward"})
    """
    if not token:
        logger.warning("[FCM] send_notification called with empty token — skipped.")
        return False

    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items()},  # FCM requires all values to be strings
        token=token,
    )

    try:
        response = messaging.send(message)
        logger.info(f"[FCM] Sent OK → {response}")
        return True
    except messaging.UnregisteredError:
        logger.warning(f"[FCM] Token unregistered (stale) — consider removing from DB: {token[:20]}...")
        return False
    except Exception as e:
        logger.error(f"[FCM] Failed to send notification: {e}")
        return False