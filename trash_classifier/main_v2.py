"""
Trash Classifier v2 — ONNX Runtime, backward-compatible endpoints.

Combines:
  - ONNX inference from the new classifier (SigLIP2, 10 classes)
  - Old endpoint paths (/predict_with_file, /predict_with_urls)
  - Enriched response with all class probabilities

Prerequisites (same directory):
    trash_classifier.onnx
    labels.json
"""

import os
import uvicorn
from io import BytesIO
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from PIL import Image
import httpx
import numpy as np
import onnxruntime as ort
import json

# ── Paths ──────────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ONNX_PATH = os.path.join(BASE_DIR, "trash_classifier.onnx")
LABELS_PATH = os.path.join(BASE_DIR, "labels.json")

# ── Global state (populated at startup) ────────────────────────────────────
session = None
labels = None
IMG_SIZE = 224  # SigLIP2-base-patch16-224

# ── Dustbin + Points maps for ALL 10 classes ──────────────────────────────
DUSTBIN_MAP = {
    "Battery":    "Red Dustbin (Hazardous Waste)",
    "Biological": "Green Dustbin (Wet / Organic Waste)",
    "Cardboard":  "Blue Dustbin (Dry Waste / Recyclable)",
    "Clothes":    "Blue Dustbin (Dry Waste / Recyclable)",
    "Glass":      "Blue Dustbin (Dry Waste / Recyclable)",
    "Metal":      "Blue Dustbin (Dry Waste / Recyclable)",
    "Paper":      "Blue Dustbin (Dry Waste / Recyclable)",
    "Plastic":    "Blue Dustbin (Dry Waste / Recyclable)",
    "Shoes":      "Blue Dustbin (Dry Waste / Recyclable)",
    "Trash":      "Black Dustbin (General / Non-Recyclable Waste)",
}

POINTS_DIC = {
    "Battery":    35,
    "Biological":  5,
    "Cardboard":   5,
    "Clothes":    10,
    "Glass":      15,
    "Metal":      25,
    "Paper":       8,
    "Plastic":    30,
    "Shoes":      10,
    "Trash":      10,
}


# ── Lifespan (load model once) ─────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    global session, labels
    print("Loading ONNX model...")
    session = ort.InferenceSession(ONNX_PATH, providers=["CPUExecutionProvider"])
    with open(LABELS_PATH) as f:
        labels = json.load(f)  # {"0": "Battery", "1": "Biological", ...}
    print(f"Ready — {len(labels)} classes loaded.")
    yield


app = FastAPI(title="Trash Classifier v2 (ONNX)", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Preprocessing (SigLIP2 normalization) ──────────────────────────────────
MEAN = np.array([0.5, 0.5, 0.5], dtype=np.float32)
STD = np.array([0.5, 0.5, 0.5], dtype=np.float32)


def preprocess(image: Image.Image) -> np.ndarray:
    image = image.convert("RGB").resize((IMG_SIZE, IMG_SIZE), Image.BICUBIC)
    arr = np.array(image, dtype=np.float32) / 255.0   # (224,224,3)
    arr = (arr - MEAN) / STD                            # normalize
    arr = arr.transpose(2, 0, 1)[np.newaxis]            # (1,3,224,224)
    return arr


def softmax(x: np.ndarray) -> np.ndarray:
    e = np.exp(x - x.max())
    return e / e.sum()


# ── Core inference (returns the enriched response dict) ────────────────────
def classify(image: Image.Image) -> dict:
    pixel_values = preprocess(image)
    logits = session.run(["logits"], {"pixel_values": pixel_values})[0][0]
    probs = softmax(logits)

    # Build {label: "XX.XX%"} for every class
    all_probabilities = {}
    for i in range(len(probs)):
        label = labels[str(i)]
        all_probabilities[label] = f"{probs[i] * 100:.2f}%"

    # Top-1 prediction
    top_idx = int(np.argmax(probs))
    predicted_class = labels[str(top_idx)]
    confidence = float(probs[top_idx])

    return {
        "predicted_class": predicted_class,
        "confidence": f"{confidence:.2%}",
        "recommended_dustbin": DUSTBIN_MAP.get(predicted_class, "Unknown"),
        "points": POINTS_DIC.get(predicted_class, 0),
        "all_probabilities": all_probabilities,
    }


# ── Request model (matches old API) ───────────────────────────────────────
class PredictRequest(BaseModel):
    image_url: str


# ── Routes ─────────────────────────────────────────────────────────────────
@app.get("/")
def root():
    return {"message": "trash classifier v2 is UP", "classes": len(labels) if labels else 0}


@app.post("/predict_with_file")
async def predict_with_file(file: UploadFile = File(...)):
    """Classify an uploaded waste image file."""
    if not file.filename:
        raise HTTPException(status_code=400, detail="No image file provided")

    try:
        image_bytes = await file.read()
        img = Image.open(BytesIO(image_bytes))
    except Exception:
        raise HTTPException(status_code=400, detail="Could not decode image.")

    try:
        result = classify(img)
        return JSONResponse(content=result)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/predict_with_urls")
async def predict_with_urls(req: PredictRequest):
    """Classify a waste image from a public URL."""
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(req.image_url)

        if resp.status_code != 200:
            raise HTTPException(status_code=400, detail="Could not download image from URL")

        img = Image.open(BytesIO(resp.content))
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=400, detail="Could not decode image from URL.")

    try:
        result = classify(img)
        return JSONResponse(content=result)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    print("http://127.0.0.1:6969")
    uvicorn.run("main_v2:app", host="0.0.0.0", port=6969, reload=True)
