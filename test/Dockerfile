FROM node:18-bookworm

# Set a working directory
WORKDIR /app

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    vim \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3016
RUN npm ping && npm install express lodash moment
