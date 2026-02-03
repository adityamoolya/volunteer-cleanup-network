from ultralytics import YOLO
import cv2
import sys
import os

# --- CONFIGURATION ---
MODEL_PATH = "waste_yolo.pt"  # Your model file
IMAGE_PATH = "metal5.jpg"     # Your test image
CONFIDENCE_THRESHOLD = 0.40   # increased to 40% to hide "nonsense" weak detections
# ---------------------

def test_model():
    # 1. Load the Model
    if not os.path.exists(MODEL_PATH):
        print(f"❌ Error: Could not find model at {MODEL_PATH}")
        return

    print(f"🚀 Loading {MODEL_PATH}...")
    model = YOLO(MODEL_PATH)

    # --- 🚨 SANITY CHECK 🚨 ---
    # This block detects if you are accidentally using the dummy base model
    first_class = model.names.get(0, "unknown")
    print(f"📋 Model knows {len(model.names)} classes.")
    
    if first_class == 'person':
        print("\n⚠️  CRITICAL WARNING ⚠️")
        print(f"   Your model thinks Class 0 is '{first_class}'.")
        print("   This means you are using the STANDARD YOLOv8 BASE MODEL.")
        print("   It has NOT learned your trash data yet.")
        print("   Please download 'best.pt' from your training run again.\n")
    else:
        print(f"✅ Good! Model Classes look custom: {list(model.names.values())[:5]}...")

    # 2. Run Prediction
    print(f"\n🔍 Analyzing {IMAGE_PATH}...")
    try:
        results = model.predict(IMAGE_PATH, conf=CONFIDENCE_THRESHOLD)
    except Exception as e:
        print(f"❌ Error during prediction: {e}")
        return

    # 3. Show Results
    result = results[0]
    
    if len(result.boxes) == 0:
        print("🤷‍♂️ No detections above confidence threshold.")
    else:
        print(f"\n--- 🎯 Found {len(result.boxes)} Objects ---")
        for box in result.boxes:
            class_id = int(box.cls[0])
            class_name = model.names[class_id]
            conf = float(box.conf[0])
            
            # Color code the console output
            icon = "🗑️"
            if "plastic" in class_name: icon = "🥤"
            elif "metal" in class_name: icon = "🥫"
            elif "glass" in class_name: icon = "🍾"
            elif "paper" in class_name: icon = "📄"

            print(f"{icon} {class_name.upper()} : {conf:.1%}")

# 4. Display Image with Terminal Interrupt Support
    annotated_frame = result.plot()

    # Resize logic (same as before)
    height, width = annotated_frame.shape[:2]
    max_height = 800
    if height > max_height:
        scale = max_height / height
        annotated_frame = cv2.resize(annotated_frame, (int(width*scale), max_height))

    cv2.imshow("YOLO Debugger", annotated_frame)
    print("\nPress 'Q' in the image window OR 'Ctrl+C' in terminal to exit...")

    # Loop that checks for Ctrl+C every 100ms
    try:
        while True:
            # Wait 100ms for a key press
            k = cv2.waitKey(100) & 0xFF
            
            # If 'q' or 'ESC' is pressed in window, break
            if k == ord('q') or k == 27:  
                break
            
            # If window is closed by 'X' button, break (requires specific backend, acts as failsafe)
            if cv2.getWindowProperty("YOLO Debugger", cv2.WND_PROP_VISIBLE) < 1:
                break

    except KeyboardInterrupt:
        print("\nCaught Ctrl+C! Closing...")

    finally:
        cv2.destroyAllWindows()