print("--- 1. SCRIPT STARTING ---")

import os
print("--- 2. IMPORTING OS DONE ---")

try:
    from ultralytics import YOLO
    print("--- 3. IMPORTING YOLO DONE ---")
except Exception as e:
    print(f"!!! CRASH IMPORTING YOLO: {e}")

import cv2
print("--- 4. IMPORTING CV2 DONE ---")

# CONFIG
MODEL_PATH = "waste_yolo.pt"
IMAGE_PATH = "metal5.jpg"

def run_test():
    print(f"--- 5. CHECKING FILES ---")
    if not os.path.exists(MODEL_PATH):
        print(f"❌ MISSING MODEL: {MODEL_PATH}")
        return
    if not os.path.exists(IMAGE_PATH):
        print(f"❌ MISSING IMAGE: {IMAGE_PATH}")
        return
        
    print(f"--- 6. LOADING MODEL ---")
    model = YOLO(MODEL_PATH)
    
    print(f"--- 7. PREDICTING ---")
    results = model.predict(IMAGE_PATH, conf=0.25)
    
    print(f"--- 8. RESULTS ---")
    if len(results[0].boxes) == 0:
        print("🤷‍♂️ No trash found.")
    else:
        for box in results[0].boxes:
            cls = int(box.cls[0])
            print(f"✅ Found: {model.names[cls]}")

    print("--- 9. SHOWING IMAGE ---")
    res_plotted = results[0].plot()
    cv2.imshow("Debug Window", res_plotted)
    print("Press ANY KEY to close window...")
    cv2.waitKey(0)
    cv2.destroyAllWindows()
    print("--- 10. FINISHED ---")

# CALL THE FUNCTION DIRECTLY (No 'if' block)
run_test()