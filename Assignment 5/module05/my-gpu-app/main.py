from flask import Flask, jsonify
import torch

app = Flask(__name__)

@app.get("/status")
def status():
    if torch.cuda.is_available():
        return jsonify({"status": "GPU enabled"})
    return jsonify({"status": "CPU enabled"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
