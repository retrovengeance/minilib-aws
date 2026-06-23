# ─────────────────────────────────────────────────────────────
#  Dockerfile — MiniLibrary Flask App
#  CCS6344 Assignment 2 — Bonus: Containerisation
#
#  ECS/Fargate is unavailable in AWS Academy Cloud Foundations.
#  Container is built and run on the EC2 instance directly.
#  nginx on the host proxies to the container on port 5000.
#
#  Build:  docker build -t minilib:latest .
#  Run:    docker run -d --name minilib \
#            --env-file /opt/minilib/.env \
#            -p 5000:5000 \
#            minilib:latest
# ─────────────────────────────────────────────────────────────

# Use slim Python base — reduces attack surface
FROM python:3.11-slim

# Security: do not run as root
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Install dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY app.py .
COPY templates/ ./templates/
COPY static/ ./static/

# Own files by non-root user
RUN chown -R appuser:appuser /app

USER appuser

# Flask runs on port 5000 — nginx proxies to this port
EXPOSE 5000

# Health check for Docker daemon (mirrors ALB health check)
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# Production: bind to all interfaces inside container
CMD ["python3", "app.py"]
