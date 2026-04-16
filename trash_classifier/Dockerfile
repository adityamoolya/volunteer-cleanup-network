FROM python:3.12-slim

WORKDIR /app

# PIL needs these system libs
RUN apt-get update && apt-get install -y \
    libglib2.0-0 libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "main_v2:app", "--host", "0.0.0.0", "--port", "6969"]