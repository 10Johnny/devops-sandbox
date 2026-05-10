from flask import Flask, jsonify
import os
import time

app = Flask(__name__)
START_TIME = time.time()

@app.route('/')
def home():
    return jsonify({
        "message": "Hello from Sandbox!",
        "env_id": os.environ.get("ENV_ID", "unknown"),
        "env_name": os.environ.get("ENV_NAME", "unknown"),
        "uptime_seconds": int(time.time() - START_TIME)
    })

@app.route('/health')
def health():
    return jsonify({
        "status": "ok",
        "timestamp": time.time()
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)
