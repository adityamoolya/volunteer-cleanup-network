#  python image
FROM python:3.9-slim

#  working directory inside the container
WORKDIR /app

# copy and install dependencies first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# copy the rest of your application code
COPY . .

# Eepose the port the app runs on
EXPOSE 8080

# command to run the application 
#$PORT is used soo the cloud provider can inject whichever port they are having
CMD ["sh","-c","uvicorn main:app --host 0.0.0.0 --port $PORT --reload"]