#!/usr/bin/env bash
# docker/push.sh – Builds and pushes both Dockerfile stages so that CI and
# team members can use them as remote build-cache layers.
#
# Usage:
#   IMAGE_REPO=ghcr.io/myorg/kivitendo-erp IMAGE_TAG=latest ./docker/push.sh
#
# Environment variables (all optional, fall back to the same defaults used by
# docker-compose.yml):
#   IMAGE_REPO   Registry + namespace + image name (default: kivitendo-erp)
#   IMAGE_TAG    Version tag                        (default: latest)

set -euo pipefail

REPO="${IMAGE_REPO:-kivitendo-erp}"
TAG="${IMAGE_TAG:-latest}"

BASE_IMAGE="${REPO}:${TAG}-base"
APP_IMAGE="${REPO}:${TAG}"

echo "==> Building base stage: ${BASE_IMAGE}"
docker build \
  --target base \
  --cache-from "${BASE_IMAGE}" \
  -t "${BASE_IMAGE}" \
  .

echo "==> Pushing ${BASE_IMAGE}"
docker push "${BASE_IMAGE}"

echo "==> Building app stage: ${APP_IMAGE}"
docker build \
  --target app \
  --cache-from "${BASE_IMAGE}" \
  --cache-from "${APP_IMAGE}" \
  -t "${APP_IMAGE}" \
  .

echo "==> Pushing ${APP_IMAGE}"
docker push "${APP_IMAGE}"

echo "==> Done. Images available:"
echo "    ${BASE_IMAGE}"
echo "    ${APP_IMAGE}"
