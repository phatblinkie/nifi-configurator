#!/bin/bash
# nifi-conf-merge.sh
# Bootstrap OR merge NiFi conf from image into host directory
#
# Behavior:
#   - If conf dir is missing or empty : full extraction from image (bootstrap)
#   - If conf dir has files           : additive merge only — never overwrites
#   - Always prints a diff summary    : highlights changed files for upgrade awareness
#
# Usage  : nifi-conf-merge.sh <image_tag>
# Example: nifi-conf-merge.sh localhost/nifi-custom:2.7.1-fips-bc
# Called automatically via systemd ExecStartPre in nifi.container quadlet
# ─────────────────────────────────────────────────────────────────────────────

IMAGE="${1:-localhost/nifi-custom:2.7.1-fips-bc}"
CONF_HOST="/mission-share/podman/containers/nifi/nifi-current/conf"
NIFI_CONF_INSIDE="/opt/nifi/nifi-current/conf"

echo "========================================"
echo " NiFi Conf Bootstrap/Merge"
echo " Image : $IMAGE"
echo " Target: $CONF_HOST"
echo "========================================"

# ── Ensure host conf directory exists ─────────────────────────────────────────
if [ ! -d "$CONF_HOST" ]; then
  echo "[init] Conf directory not found — creating: $CONF_HOST"
  mkdir -p "$CONF_HOST"
  if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to create conf directory: $CONF_HOST"
    exit 1
  fi
fi

# ── Extract image defaults into a temp directory ───────────────────────────────
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "[init] Extracting defaults from image..."
podman run --rm \
  -v "${TMPDIR}:/tmp/conf-src:z" \
  --entrypoint /bin/bash \
  "$IMAGE" \
  -c "cp -rp ${NIFI_CONF_INSIDE}/. /tmp/conf-src/ && echo '[init] Image extraction complete.'"

if [ $? -ne 0 ]; then
  echo "[ERROR] Failed to extract conf from image: $IMAGE"
  exit 1
fi

# ── Bootstrap vs merge decision ────────────────────────────────────────────────
HOST_FILE_COUNT=$(find "$CONF_HOST" -type f 2>/dev/null | wc -l)

if [ "$HOST_FILE_COUNT" -eq 0 ]; then
  echo ""
  echo "[init] Conf directory is empty — performing full bootstrap copy..."
  cp -rp "$TMPDIR"/. "$CONF_HOST"/
  if [ $? -ne 0 ]; then
    echo "[ERROR] Bootstrap copy failed."
    exit 1
  fi
  echo "[init] Bootstrap complete."
  echo ""
  echo "Files seeded:"
  ls -lh "$CONF_HOST"
  exit 0
fi

# ── Additive merge (conf dir already has files) ────────────────────────────────
echo ""
echo "[init] Existing conf detected — performing additive merge..."
echo "       (existing files are never overwritten)"
echo ""

ADDED=0
SKIPPED=0

for src_file in "$TMPDIR"/*; do
  filename=$(basename "$src_file")
  dest_file="$CONF_HOST/$filename"

  if [ ! -e "$dest_file" ]; then
    cp -p "$src_file" "$dest_file"
    echo "  ✔ ADDED   → $filename"
    ((ADDED++))
  else
    echo "  ─ KEPT    → $filename"
    ((SKIPPED++))
  fi
done

echo ""
echo "[init] Merge complete — Added: $ADDED  |  Kept existing: $SKIPPED"

# ── Diff summary (upgrade awareness) ──────────────────────────────────────────
DIFFS=0
for src_file in "$TMPDIR"/*; do
  filename=$(basename "$src_file")
  dest_file="$CONF_HOST/$filename"
  if [ -e "$dest_file" ] && ! diff -q "$dest_file" "$src_file" > /dev/null 2>&1; then
    if [ $DIFFS -eq 0 ]; then
      echo ""
      echo "=== Files that differ from image defaults (review for breaking changes) ==="
    fi
    echo ""
    echo "  ⚠  CHANGED: $filename"
    diff "$dest_file" "$src_file" | grep "^[<>]" | head -10
    ((DIFFS++))
  fi
done

if [ $DIFFS -eq 0 ]; then
  echo ""
  echo "[init] ✔ All existing files match image defaults — no breaking changes detected."
fi

echo ""
echo "[init] Done."
exit 0
