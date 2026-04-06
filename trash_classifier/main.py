"""
Lean trash classifier — ONNX Runtime only, no torch.

Prerequisites (in same directory):
    trash_classifier.onnx
    labels.json

Both are produced by export_onnx.py
"""

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from pydantic import BaseModel
from PIL import Image
from io import BytesIO
import httpx
import numpy as np
import onnxruntime as ort
import json

# ── Load artifacts at startup ──────────────────────────────────────────────
ONNX_PATH   = "trash_classifier.onnx"
LABELS_PATH = "labels.json"

session = None
labels  = None
IMG_SIZE = 224  # SigLIP2-base-patch16-224

@asynccontextmanager
async def lifespan(app: FastAPI):
    global session, labels
    print("Loading ONNX model...")
    session = ort.InferenceSession(ONNX_PATH, providers=["CPUExecutionProvider"])
    with open(LABELS_PATH) as f:
        labels = json.load(f)      # keys are strings: "0", "1", ...
    print(f"Ready. {len(labels)} classes.")
    yield

app = FastAPI(title="Trash Classifier (ONNX)", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Preprocessing (replaces AutoImageProcessor at runtime) ─────────────────
MEAN = np.array([0.5, 0.5, 0.5], dtype=np.float32)
STD  = np.array([0.5, 0.5, 0.5], dtype=np.float32)

def preprocess(image: Image.Image) -> np.ndarray:
    image = image.convert("RGB").resize((IMG_SIZE, IMG_SIZE), Image.BICUBIC)
    arr   = np.array(image, dtype=np.float32) / 255.0     # (224,224,3)
    arr   = (arr - MEAN) / STD                             # normalize
    arr   = arr.transpose(2, 0, 1)[np.newaxis]             # (1,3,224,224)
    return arr

def softmax(x: np.ndarray) -> np.ndarray:
    e = np.exp(x - x.max())
    return e / e.sum()

# ── Inference ──────────────────────────────────────────────────────────────
def run_inference(image: Image.Image, top_k: int = 3):
    pixel_values = preprocess(image)
    logits = session.run(["logits"], {"pixel_values": pixel_values})[0][0]
    probs  = softmax(logits)
    ranked = sorted(
        [{"label": labels[str(i)], "confidence": round(float(probs[i]), 4)}
         for i in range(len(probs))],
        key=lambda x: -x["confidence"]
    )
    return ranked[:top_k]

# ── Routes ─────────────────────────────────────────────────────────────────
@app.get("/")
def root():
    return {"status": "ok", "backend": "onnxruntime", "classes": len(labels)}

@app.post("/classify/upload")
async def classify_upload(file: UploadFile = File(...), top_k: int = 3):
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image.")
    try:
        img = Image.open(BytesIO(await file.read()))
    except Exception:
        raise HTTPException(status_code=400, detail="Could not decode image.")
    return {"source": file.filename, "results": run_inference(img, top_k)}

class URLRequest(BaseModel):
    url: str
    top_k: int = 3

@app.post("/classify/url")
async def classify_url(req: URLRequest):
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(req.url)
        r.raise_for_status()
        img = Image.open(BytesIO(r.content))
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=400, detail=f"Could not fetch URL: {e}")
    except Exception:
        raise HTTPException(status_code=400, detail="Could not decode image from URL.")
    return {"source": req.url, "results": run_inference(img, req.top_k)}
