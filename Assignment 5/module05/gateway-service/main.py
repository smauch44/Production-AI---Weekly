from flask import Flask, jsonify
import os
import requests

app = Flask(__name__)

# Read environment variable and split into list of URLs
GPU_APP_URLS = os.getenv("GPU_APP_URLS", "")
GPU_ENDPOINTS = [url.strip() for url in GPU_APP_URLS.split(",") if url.strip()]

@app.route("/aggregate", methods=["GET"])
def aggregate_predictions():
    responses = []

    for url in GPU_ENDPOINTS:
        try:
            full_url = f"{url}/status"
            res = requests.get(full_url, timeout=5)
            res.raise_for_status()
            responses.append({
                "url": full_url,
                "status": "success",
                "response": res.json()
            })
        except Exception as e:
            responses.append({
                "url": url,
                "status": "error",
                "error": str(e)
            })

    return jsonify({
        "aggregated": responses
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)