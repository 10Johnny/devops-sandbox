FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y stress-ng && rm -rf /var/lib/apt/lists/*

RUN pip install flask

COPY app.py .

EXPOSE 3000

CMD ["python", "app.py"]
