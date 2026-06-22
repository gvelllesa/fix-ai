FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY . .

# Railway injects PORT as an env var; default to 8000 for local runs.
ENV PORT=8000
EXPOSE 8000

# Use shell form so $PORT is expanded by the shell at runtime.
CMD uvicorn main:app --host 0.0.0.0 --port ${PORT}
