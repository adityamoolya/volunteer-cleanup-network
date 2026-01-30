from ultralytics import YOLO
import cv2
import sys
import os

# --- CONFIGURATION ---
MODEL_PATH = "waste_yolo.pt"  # Path to your trained model
IMAGE_PATH = "metal5.jpg" # Change this to your image name
# ---------------------

def test_model():
    # 1. Load the Model
    if not os.path.exists(MODEL_PATH):
        print(f"❌ Error: Could not find model at {MODEL_PATH}")
        print("   Did you forget to put best.pt in this folder?")
        return

    print(f"🚀 Loading {MODEL_PATH}...")
    model = YOLO(MODEL_PATH)

    # 2. Run Prediction
    # conf=0.25 means "Ignore anything less than 25% confident"
    results = model.predict(IMAGE_PATH, conf=0.25)

    # 3. Show Results in Terminal
    print("\n--- 🔍 DETECTION RESULTS ---")
    result = results[0] # Get first image result
    
    if len(result.boxes) == 0:
        print("🤷‍♂️ No trash detected.")
    else:
        for box in result.boxes:
            class_id = int(box.cls[0])
            class_name = model.names[class_id]
            confidence = float(box.conf[0])
            print(f"✅ Found: {class_name.upper()} ({confidence:.1%})")

    # 4. Show Image with Boxes (Popup Window)
    # result.plot() creates a numpy array with boxes drawn
    annotated_frame = result.plot()

    # Resize if image is too big for screen
    height, width = annotated_frame.shape[:2]
    if height > 800:
        scale = 800 / height
        annotated_frame = cv2.resize(annotated_frame, (int(width*scale), 800))

    cv2.imshow("YOLO Waste Detection", annotated_frame)
    print("\nPress any key in the image window to exit...")
    cv2.waitKey(0)
    cv2.destroyAllWindows()

if __name__ == "__main__":
    test_model()