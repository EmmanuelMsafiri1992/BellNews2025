# ---------- BUILDER ----------
FROM python:3.12.8-slim-bookworm AS builder

# Install build tools (removed in final image)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
        g++ \
        python3-dev \
        build-essential \
        libc6-dev \
        make \
        libasound2-dev \
        alsa-utils \
        libasound2 \
        portaudio19-dev \
        libsndfile1 \
        pkg-config \
        libffi-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create venv
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements.txt


# ---------- RUNTIME ----------
FROM python:3.12.8-slim-bookworm

# Runtime deps only (no compilers, no build-essential)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libasound2 \
        alsa-utils \
        portaudio19-dev \
        libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /bellapp

# Copy venv from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy app code
COPY . .

EXPOSE 5000 5001
ENV PYTHONUNBUFFERED=1
ENV IN_DOCKER=1

CMD ["python", "launch_vcns_timer.py"]
