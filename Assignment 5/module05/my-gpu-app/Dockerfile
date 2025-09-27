FROM python:3.10
WORKDIR /app
COPY . /app
RUN pip install --upgrade pip setuptools wheel
RUN pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 8000
CMD ["python", "main.py"]
