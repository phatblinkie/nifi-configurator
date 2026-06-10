#!/bin/bash
# nifi-extract-conf.sh
# Extracts the NiFi conf directory from a container or image to the host
# Usage: ./nifi-extract-conf.sh [destination_path]
# ─────────────────────────────────────────────────────────────────────

# ── Config — edit these to match your environment ─────────────────────────────
NIFI_IMAGE="localhost/nifi-custom:2.7.1-fips-bc"
CONTAINER_NAME="nifi-nifi"                      # podman pod format: <pod>-<container>
NIFI_CONF_INSIDE="/opt/nifi/nifi-current/conf"
DEFAULT_DEST="/mission-share/podman/containers/nifi/nifi-current/conf"
# ──────────────────────────────────────────────────────────────────────────────

DEST="${1:-$DEFAULT_DEST}"

echo "=== NiFi Conf Extractor ==="
echo "Destination: $DEST"
echo ""

# Safety check — don't overwrite an existing populated conf dir
if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  echo "⚠  WARNING: $DEST already exists and is not empty."
  echo "   This script is for initial extraction only."
  echo "   If you want to re-extract, manually move or remove the existing dir first."
  echo ""
  echo "   To back it up first:"
  echo "   mv $DEST ${DEST}.bak-$(date +%Y%m%d-%H%M%S)"
  exit 1
fi

mkdir -p "$DEST"

# ── Case 1: Container is currently running ─────────────────────────────────────
if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
  echo "✔  Container '$CONTAINER_NAME' is running — copying conf via podman cp..."
  podman cp "${CONTAINER_NAME}:${NIFI_CONF_INSIDE}/." "$DEST/"
  STATUS=$?

# ── Case 2: Container exists but is stopped ────────────────────────────────────
elif podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
  echo "✔  Container '$CONTAINER_NAME' is stopped — copying conf via podman cp..."
  podman cp "${CONTAINER_NAME}:${NIFI_CONF_INSIDE}/." "$DEST/"
  STATUS=$?

# ── Case 3: No container — spin up a temporary one from the image ──────────────
else
  echo "ℹ  No container found — running a temporary container from image..."
  echo "   Image: $NIFI_IMAGE"
  podman run --rm \
    -v "${DEST}:/tmp/conf-out:z" \
    --entrypoint /bin/bash \
    "$NIFI_IMAGE" \
    -c "cp -rp ${NIFI_CONF_INSIDE}/. /tmp/conf-out/ && echo 'Copy complete.'"
  STATUS=$?
fi

# ── Result ─────────────────────────────────────────────────────────────────────
echo ""
if [ $STATUS -eq 0 ]; then
  FILE_COUNT=$(find "$DEST" -type f | wc -l)
  echo "✔  Success! $FILE_COUNT files extracted to: $DEST"
  echo ""
  echo "Files:"
  ls -lh "$DEST"
  echo ""
  echo "Next steps:"
  echo "  1. Review/customize the conf files if needed"
  echo "  2. Add the conf hostPath volume to your pod YAML"
  echo "  3. Add the initContainer merge block to your pod YAML"
  echo "  4. Recreate the pod: podman pod rm nifi && podman play kube nifi-pod/nifi-pod.yml"
else
  echo "✖  Extraction failed (exit code $STATUS)"
  echo "   Check the output above for errors."
  rmdir "$DEST" 2>/dev/null   # clean up empty dir if we created it
  exit $STATUS
fi
