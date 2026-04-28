#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-.}"
ALEMBIC_CONFIG="${ALEMBIC_CONFIG:-${APP_DIR}/alembic.ini}"

require_env() {
    var_name="$1"
    eval "var_value=\${$var_name:-}"
    if [ -z "$var_value" ]; then
        echo "$var_name is required." >&2
        exit 1
    fi
}

require_env DATABASE_URL

if [ ! -f "$ALEMBIC_CONFIG" ]; then
    echo "Alembic config not found at $ALEMBIC_CONFIG." >&2
    exit 1
fi

if [ ! -f "${APP_DIR}/alembic/env.py" ]; then
    echo "Alembic env.py not found at ${APP_DIR}/alembic/env.py." >&2
    exit 1
fi

cd "$APP_DIR"

wait_for_migrations() {
    attempt=1
    max_attempts="${DB_MIGRATION_MAX_ATTEMPTS:-20}"
    sleep_seconds="${DB_MIGRATION_RETRY_DELAY_SECONDS:-3}"

    while [ "$attempt" -le "$max_attempts" ]; do
        if alembic -c "$ALEMBIC_CONFIG" upgrade head; then
            return 0
        fi

        if [ "$attempt" -lt "$max_attempts" ]; then
            echo "Migration attempt ${attempt} failed. Waiting for database..." >&2
            sleep "$sleep_seconds"
        fi

        attempt=$((attempt + 1))
    done

    echo "Database migrations failed after ${max_attempts} attempts." >&2
    return 1
}

wait_for_migrations

PAYMENT_PROVIDER_MODE="${PAYMENT_PROVIDER_MODE:-mock}"

if [ "$PAYMENT_PROVIDER_MODE" != "live" ]; then
    exec "$@"
fi

if [ -z "${APP_BASE_URL:-}" ]; then
    echo "Warning: APP_BASE_URL is missing; skipping webhook registration." >&2
    exec "$@"
fi

if [ -z "${PAYMENT_WEBHOOK_PATH:-}" ]; then
    echo "Warning: PAYMENT_WEBHOOK_PATH is missing; skipping webhook registration." >&2
    exec "$@"
fi

APP_BASE_URL="$(printf '%s' "$APP_BASE_URL" | sed 's#/*$##')"

case "$APP_BASE_URL" in
    http://*|https://*) ;;
    *)
        echo "Warning: APP_BASE_URL must start with http:// or https://; skipping webhook registration." >&2
        exec "$@"
        ;;
esac

case "$PAYMENT_WEBHOOK_PATH" in
    /*) ;;
    *)
        echo "Warning: PAYMENT_WEBHOOK_PATH must start with /; skipping webhook registration." >&2
        exec "$@"
        ;;
esac

# Keep shell registration logic aligned with the Python gateway, which derives
# the callback from APP_BASE_URL + PAYMENT_WEBHOOK_PATH.
FULL_WEBHOOK_URL="${APP_BASE_URL}${PAYMENT_WEBHOOK_PATH}"
export APP_BASE_URL PAYMENT_WEBHOOK_PATH FULL_WEBHOOK_URL
echo "Webhook callback URL resolved to ${FULL_WEBHOOK_URL}." >&2
exec "$@"
