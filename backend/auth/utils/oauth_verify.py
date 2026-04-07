"""
    File: backend/auth/utils/oauth_verify.py
    Description: 
        Verifies Supabase OAuth JWT tokens.
        Supports both ES256 (new Supabase default) and HS256 (legacy).
"""

from jose import jwt, JWTError, jwk
from jose.utils import base64url_decode
from dotenv import load_dotenv
import os
import logging
import httpx
import json

load_dotenv()

logger = logging.getLogger(__name__)

SUPABASE_JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET")
SUPABASE_URL = os.getenv("SUPABASE_URL")

# Cache the JWKS keys so we don't fetch on every request
_jwks_cache = None

def _get_jwks():
    """Fetch the JWKS public keys from Supabase (cached after first call)."""
    global _jwks_cache
    if _jwks_cache is not None:
        return _jwks_cache
    
    try:
        jwks_url = f"{SUPABASE_URL}/auth/v1/.well-known/jwks.json"
        logger.info(f"Fetching JWKS from: {jwks_url}")
        resp = httpx.get(jwks_url, timeout=10)
        resp.raise_for_status()
        _jwks_cache = resp.json()
        logger.info(f"JWKS fetched successfully: {len(_jwks_cache.get('keys', []))} keys")
        return _jwks_cache
    except Exception as e:
        logger.error(f"Failed to fetch JWKS: {e}")
        return None


def verify_supabase_token(token: str) -> dict:
    """
    Verify a Supabase-issued JWT token.
    Tries ES256 (JWKS public key) first, falls back to HS256 (shared secret).
    """
    try:
        # Peek at the token header to determine the algorithm
        header = jwt.get_unverified_header(token)
        alg = header.get("alg", "HS256")
        kid = header.get("kid")
        
        logger.info(f"Token algorithm: {alg}, kid: {kid}")

        if alg == "ES256":
            # New Supabase: uses asymmetric ES256 signing
            payload = _verify_es256(token, kid)
        else:
            # Legacy Supabase: uses symmetric HS256 signing
            payload = jwt.decode(
                token,
                SUPABASE_JWT_SECRET,
                algorithms=["HS256"],
                options={"verify_aud": False}
            )

        if payload is None:
            return None

        logger.info(f"Token decoded! Email: {payload.get('email')}, Sub: {payload.get('sub')}")

        email = payload.get("email")
        sub   = payload.get("sub")

        if not email or not sub:
            logger.warning(f"Token missing email or sub. Email: {email}, Sub: {sub}")
            return None

        return {
            "email": email,
            "provider_user_id": sub,
            "provider": payload.get("app_metadata", {}).get("provider", "github")
        }

    except JWTError as e:
        logger.error(f"JWT verification FAILED: {type(e).__name__}: {e}")
        return None
    except Exception as e:
        logger.error(f"Unexpected error verifying token: {type(e).__name__}: {e}")
        return None


def _verify_es256(token: str, kid: str) -> dict:
    """Verify an ES256-signed JWT using Supabase JWKS public key."""
    jwks = _get_jwks()
    if not jwks:
        logger.error("No JWKS available — cannot verify ES256 token")
        return None

    # Find the matching key by kid
    matching_key = None
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            matching_key = key
            break

    if not matching_key:
        logger.error(f"No JWKS key found matching kid: {kid}")
        # Try the first key as fallback
        keys = jwks.get("keys", [])
        if keys:
            matching_key = keys[0]
            logger.info(f"Using first available JWKS key: {matching_key.get('kid')}")
        else:
            return None

    # Construct the public key and verify
    public_key = jwk.construct(matching_key, algorithm="ES256")
    
    payload = jwt.decode(
        token,
        public_key,
        algorithms=["ES256"],
        options={"verify_aud": False}
    )
    
    return payload