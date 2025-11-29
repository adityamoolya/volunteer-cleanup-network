# backend/routers/images.py

import os
import cloudinary
import cloudinary.uploader
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from PIL import Image
import io
import uuid

from auth_utils import get_current_active_user
import schemas

router = APIRouter(
    prefix="/images",
    tags=["Images"]
)

# Check for Test Mode
# USE_MOCK_CLOUD = os.getenv("USE_MOCK_CLOUD") == "True"

# Only configure if NOT in mock mode
cloudinary.config(
      cloud_name = os.getenv("CLOUDINARY_CLOUD_NAME"),
      api_key = os.getenv("CLOUDINARY_API_KEY"),
      api_secret = os.getenv("CLOUDINARY_API_SECRET")
    )

@router.post("/upload/")
async def upload_image(
    file: UploadFile = File(...),
    current_user: schemas.User = Depends(get_current_active_user)
):
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="File provided is not an image.")

    # --- MOCK MODE: Bypass Cloudinary completely ---
    # if USE_MOCK_CLOUD:
    #     print(f"⚠️ MOCK UPLOAD: Pretending to upload {file.filename}")
    #     # Return a fake URL (random Lorem Picsum image or similar)
    #     fake_id = str(uuid.uuid4())
    #     return {
    #         "message": "Mock Image uploaded successfully!",
    #         "url": f"https://picsum.photos/seed/{fake_id}/800/600", 
    #         "public_id": f"mock_id_{fake_id}"
    #     }
    # # -----------------------------------------------

    try:
        contents = await file.read()
        img = Image.open(io.BytesIO(contents))
        img.thumbnail((1920, 1080))
        
        processed_image_io = io.BytesIO()
        img.save(processed_image_io, format='WEBP', quality=85)
        processed_image_io.seek(0)

        upload_result = cloudinary.uploader.upload(
            processed_image_io,
            folder="community_app_posts"
        )
        
        return {
            "message": "Image uploaded successfully!",
            "url": upload_result.get("secure_url"),
            "public_id": upload_result.get("public_id")
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error uploading file: {e}"
        )