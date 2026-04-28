FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /srv/bot

COPY requirements.txt /srv/bot/requirements.txt

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && pip install --no-cache-dir -r /srv/bot/requirements.txt \
    && rm -rf /var/lib/apt/lists/*

COPY . /srv/bot

RUN chmod +x /srv/bot/entrypoint.sh

ENTRYPOINT ["/srv/bot/entrypoint.sh"]
CMD ["python", "main.py"]
