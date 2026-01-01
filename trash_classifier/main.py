import os
from io import BytesIO
import uvicorn
import numpy as np
import tensorflow as tf
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from PIL import Image

app = FastAPI(title="Waste Classifier API")

# load model 
MODEL_PATH = 'waste_classifier_model.h5'
model = tf.keras.models.load_model(MODEL_PATH)
CLASS_NAMES = ['cardboard', 'glass', 'metal', 'paper', 'plastic', 'trash']
DUSTBIN_MAP = {
    'cardboard': '🔵 Blue Dustbin (Dry Waste / Recyclable)',
    'glass': '🔵 Blue Dustbin (Dry Waste / Recyclable)',
    'metal': '🔵 Blue Dustbin (Dry Waste / Recyclable)',
    'paper': '🔵 Blue Dustbin (Dry Waste / Recyclable)',
    'plastic': '🔵 Blue Dustbin (Dry Waste / Recyclable)',
    'trash': '⚫ Black Dustbin (General / Non-Recyclable Waste)'
}

#prepares the image for model prediction
def preprocess_image(image_bytes: bytes) -> np.ndarray:
    
    img = Image.open(BytesIO(image_bytes)).convert('RGB')
    img = img.resize((224, 224))
    img_array = tf.keras.preprocessing.image.img_to_array(img)
    img_array = np.expand_dims(img_array, axis=0)
    preprocessed_img = tf.keras.applications.mobilenet_v2.preprocess_input(img_array)
    return preprocessed_img

# prediction Endpoint 
@app.post("/predict")
async def predict(file: UploadFile = File(...)):
    """Predicts the class of uploaded waste image."""
    if not file.filename:
        raise HTTPException(status_code=400, detail="No image file provided")

    try:
        image_bytes = await file.read()
        processed_image = preprocess_image(image_bytes)

        prediction = model.predict(processed_image)
        score = tf.nn.softmax(prediction[0])
        predicted_class = CLASS_NAMES[np.argmax(score)]
        confidence = float(np.max(score))

        return JSONResponse(content={
            'predicted_class': predicted_class,
            'confidence': f"{confidence:.2%}",
            'recommended_dustbin': DUSTBIN_MAP.get(predicted_class)
        })
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/")
def root():
    return{"trash classifier is UP"}


if __name__ == "__main__":
    print("http://127.0.0.1:6969") #this should produce a link fir microservice
    uvicorn.run("main:app", host="0.0.0.0", port=6969, reload=True)
