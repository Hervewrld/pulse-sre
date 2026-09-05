#!/bin/sh
# Regenerates the Postgres datasource provisioning file from environment
# variables at container start, instead of baking DB_HOST/DB_USER/etc into
# the image at build time - this image is shared across dev/prod (same ECR
# repo, different task definitions), so the connection details have to come
# from the environment, not the build.
set -eu

# RDS's manage_master_user_password (terraform/modules/rds) generates a
# random password from the full printable-ASCII set, minus a handful of SQL-
# unfriendly characters - not minus YAML-unfriendly ones. Interpolated
# unquoted, a password containing e.g. "#" would silently truncate at that
# character (YAML comment), or ":" could break parsing outright - this only
# ever showed up as a real bug once tested against something other than
# docker-compose's plain "pulse" password, which has no special characters
# to expose it. yaml_quote wraps a value in a YAML double-quoted string,
# escaping the two characters that would otherwise break out of one.
yaml_quote() {
  escaped=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '"%s"' "$escaped"
}

cat > /etc/grafana/provisioning/datasources/postgres.yml <<EOF
apiVersion: 1

datasources:
  - name: Pulse Postgres
    uid: pulse-postgres
    type: postgres
    access: proxy
    url: $(yaml_quote "${DB_HOST}:${DB_PORT}")
    database: $(yaml_quote "${DB_NAME}")
    user: $(yaml_quote "${DB_USER}")
    isDefault: true
    jsonData:
      # Grafana's Postgres datasource only accepts disable/require/verify-ca/
      # verify-full here - not libpq's usual "prefer" (confirmed by actually
      # hitting this datasource's /health endpoint: it rejected "prefer"
      # outright with "unsupported sslmode"). There's no single value that's
      # both safe against RDS and works against docker-compose's plain
      # postgres:16-alpine (no SSL configured there at all, also confirmed by
      # testing - "require" fails the same way "disable" would fail against
      # RDS), so this has to be a real env var, not a hardcoded default.
      sslmode: ${DB_SSLMODE:-require}
      postgresVersion: 1600
    secureJsonData:
      password: $(yaml_quote "${DB_PASSWORD}")
    editable: false
EOF

exec /run.sh "$@"
