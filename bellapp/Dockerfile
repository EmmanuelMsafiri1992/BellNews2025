# Use a specific tag to ensure we get the right version
FROM python:3.12.8-slim-bookworm

# Install all build deps in one layer and clean manually
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
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*

# Verify Python
RUN python3 --version && which python3

WORKDIR /bellapp

# Copy and install requirements in a virtual environment
COPY requirements.txt .
RUN python3 -m venv venv
RUN venv/bin/pip install --upgrade pip setuptools wheel
RUN venv/bin/pip install --no-cache-dir -v -r requirements.txt

# Copy application code
COPY . .

# Optional: remove build deps to slim image (uncomment if needed)
# RUN apt-get purge -y gcc g++ python3-dev build-essential libc6-dev make pkg-config libffi-dev \
#     && apt-get autoremove -y \
#     && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*

EXPOSE 5000 5001
ENV PYTHONUNBUFFERED=1
ENV IN_DOCKER=1
CMD ["venv/bin/python3", "launch_vcns_timer.py"]
