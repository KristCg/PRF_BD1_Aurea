FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOST=0.0.0.0 \
    PORT=8000

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --create-home --uid 10001 aurea

COPY --chown=aurea:aurea server.py seed.py ./
COPY --chown=aurea:aurea db/ ./db/
COPY --chown=aurea:aurea static/ ./static/
COPY --chown=aurea:aurea docker/ ./docker/

USER aurea
EXPOSE 8000
CMD ["python", "-m", "docker.entrypoint"]
