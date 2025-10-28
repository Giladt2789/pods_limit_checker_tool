FROM python:3.13-slim

# Install curl for uv installer
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Install uv using official installer
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Add uv to PATH
ENV PATH="/root/.local/bin:$PATH"

WORKDIR /app

# Copy project files
COPY pyproject.toml uv.lock* ./
COPY k8s_pod_limits_checker.py ./

# Install dependencies using uv
RUN uv sync --frozen

# Set the entrypoint to run the app with uv
ENTRYPOINT ["uv", "run", "k8s_pod_limits_checker.py"]