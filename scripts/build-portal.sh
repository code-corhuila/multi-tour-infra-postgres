#!/bin/sh
# Builds the identity-audit portal and copies its single ES module into the front, which serves it from its own
# origin (the manifest of the front points to portals/identity-audit-portal.js). Run it before scripts/up.sh:
# the front image takes the file at build time.
# PORTAL_DIR and FRONT_DIR replace the folders when the repositories do not sit beside this one.
set -eu
cd "$(dirname "$0")/.."

portal="${PORTAL_DIR:-../multi-tour-identity-audit-portal}"
front="${FRONT_DIR:-../multi-tour-front}"
for dir in "$portal" "$front"; do
  if [ ! -d "$dir" ]; then
    echo "ERROR: $dir does not exist. Clone the repository there or set PORTAL_DIR / FRONT_DIR." >&2
    exit 1
  fi
done

(cd "$portal" && npm ci && npm run build)
mkdir -p "$front/portals"
cp "$portal/dist/portal.js" "$front/portals/identity-audit-portal.js"
cp "$portal/dist/portal.css" "$front/portals/identity-audit-portal.css"
echo "Copied to $front/portals/identity-audit-portal.js and .css"
