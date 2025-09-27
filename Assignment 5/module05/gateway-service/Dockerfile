# Use the official Python image from the Docker Hub
FROM python:3.10

# Set the working directory in the container
WORKDIR /app

ENV GPU_APP_URLS="http://gpu-app1:8000,http://gpu-app2:8000,http://gpu-app3:8000"

# Copy the current directory contents into the container at /app
COPY . /app

# Install any remaining packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Make port 80 available to the world outside this container
EXPOSE 5000

# Run main.py when the container launches
CMD ["python", "main.py"]