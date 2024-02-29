FROM python:3.11-slim AS base
WORKDIR /app
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

FROM base AS builder
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.11-alpine AS final
RUN adduser --disabled-password appuser
USER appuser
COPY --from=builder --chown=appuser:appuser /usr/local/lib/python3.11/site-packages/ /usr/local/lib/python3.11/site-packages/
COPY --chown=appuser:appuser . .
HEALTHCHECK --interval=30s --timeout=5s \
  CMD curl -f http://localhost/healthz || exit 1
EXPOSE 8000
CMD ["python", "main.py", "--kubeconfig", "kubeconfig", "--address", ":8080"]