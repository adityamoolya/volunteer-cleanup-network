from ultralytics import YOLO

def train():
    # 1. Load the model. "yolov8n.pt" is the Nano version (Fastest/Smallest).
    # If you have a good GPU (RTX 3060+), try "yolov8s.pt" (Small) or "yolov8m.pt" (Medium) for better accuracy.
    model = YOLO('yolov8n.pt') 

    # 2. Train the model
    results = model.train(
        data=r"D:\El\envirormentEL\train_ml\archive (2)\YOLO-Waste-Detection-1\YOLO-Waste-Detection-1\data.yaml", # Path to your yaml
        epochs=50,             # 50 epochs is usually enough for YOLO
        imgsz=640,             # YOLO standard image size
        batch=16,              # Adjust based on your GPU memory
        name='waste_yolo_v8',  # Name of the project folder
        device=0               # Use GPU 0
    )

    # 3. Validation
    metrics = model.val()
    print(f"Maps: {metrics.box.map}") # Mean Average Precision

    # 4. Export to ONNX (Optional, good for deployment)
    model.export(format='onnx')

if __name__ == '__main__':
    train()