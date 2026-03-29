from jose import jwt, JWTError
from dotenv import load_dotenv
import os

load_dotenv()

SUPABASE_JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET")

def verify_supabase_token(token: str) -> dict:
    try:
        payload = jwt.decode(
            token,
            SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            options={"verify_aud": False}  # Supabase doesn't always set audience
        )

        email = payload.get("email")
        sub   = payload.get("sub")        # Supabase user ID

        if not email or not sub:
            return None

        return {
            "email": email,
            "provider_user_id": sub,
            "provider": payload.get("app_metadata", {}).get("provider", "github")
        }

    except JWTError:
        return None