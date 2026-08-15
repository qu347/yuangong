FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=config.settings.production

WORKDIR /app/backend

COPY backend/requirements /app/backend/requirements
RUN python -m pip install --no-cache-dir -r requirements/production.txt

COPY backend /app/backend

# 该镜像仅提供安全基线检查，不代表已完成生产部署。
CMD ["python", "manage.py", "check", "--deploy"]
