#!/usr/bin/env bash
# Generate cryptographically-strong local auth secrets (AUTH_SECRET,
# NEXTAUTH_SECRET, JWT_SECRET, etc.) and write them to the incident folder.
# Never prints secret values to stdout — only destinations, so chat stays clean.
#
# Usage:
#   ./generate-secrets.sh AUTH_SECRET NEXTAUTH_SECRET JWT_SECRET SESSION_SECRET
#
# If no args are given, generates the default five.

set -euo pipefail
command -v openssl >/dev/null || { echo "openssl required"; exit 1; }

OUT="$HOME/incident-$(date +%Y%m%d)"
mkdir -p "$OUT"
chmod 700 "$OUT"

FILE="$OUT/secrets.txt"
touch "$FILE"
chmod 600 "$FILE"

# Defaults if nothing passed
if [ $# -eq 0 ]; then
  set -- AUTH_SECRET NEXTAUTH_SECRET JWT_SECRET BETTER_AUTH_SECRET SESSION_SECRET
fi

{
  echo ""
  echo "# Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} >> "$FILE"

for NAME in "$@"; do
  VALUE=$(openssl rand -hex 32)
  echo "$NAME=$VALUE" >> "$FILE"
  echo "  $NAME — 64-char hex, written" >&2
done

echo "" >&2
echo "  file: $FILE (chmod 600)" >&2
echo "  warning: rotating these env vars invalidates all existing user sessions." >&2
