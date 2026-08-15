#!/bin/sh
set -eu

python - <<'PY'
import os
import time

import psycopg

deadline = time.monotonic() + 60
while True:
    try:
        with psycopg.connect(
            dbname=os.environ["POSTGRES_DB"],
            user=os.environ["POSTGRES_USER"],
            password=os.environ["POSTGRES_PASSWORD"],
            host=os.environ.get("POSTGRES_HOST", "db"),
            port=os.environ.get("POSTGRES_PORT", "5432"),
            connect_timeout=3,
        ):
            break
    except psycopg.OperationalError:
        if time.monotonic() >= deadline:
            raise SystemExit("PostgreSQL did not become ready within 60 seconds")
        time.sleep(2)
PY

python manage.py migrate --noinput
exec python manage.py runserver 0.0.0.0:8000
