#!/bin/bash
#
# push_images.sh <dev|prod>
#
# Builds api/scheduler/checker (one shared image, see docker/Dockerfile,
# selected at runtime by the SERVICE env var) plus grafana (its own image,
# docker/grafana/Dockerfile, with Pulse's SLO dashboard baked in - Phase 11)
# and pushes each to that environment's ECR repository, tagged with the
# current git commit.
#
# ECR repositories are IMMUTABLE (terraform/modules/ecr) - re-pushing an existing
# tag fails on purpose, so every push needs a new tag. The commit SHA gives that
# for free and doubles as a trail back to the exact code that's running - which
# only holds if the tree is clean, hence the check below.
#
# Only needs ecr_repository_urls (already output by Phase 5's ECR module) - not
# a fresh apply of this PR's Terraform, which itself needs an image_tag to plan.
#
# After this succeeds, deploy it with:
#   terraform -chdir=terraform/environments/<env> apply -var image_tag=<the printed tag>

set -euo pipefail

ENVIRONMENT="${1:?Usage: push_images.sh <dev|prod>}"
SERVICES=(api scheduler checker grafana)
TF_DIR="terraform/environments/${ENVIRONMENT}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has uncommitted changes - commit or stash first, so the pushed" >&2
  echo "image's tag actually matches the code that's running." >&2
  exit 1
fi

IMAGE_TAG="$(git rev-parse --short HEAD)"
REGION="$(aws configure get region)"

REPO_URLS_JSON="$(terraform -chdir="${TF_DIR}" output -json ecr_repository_urls)"

# One parse of REPO_URLS_JSON into REPO_URL_<service>=<url> assignments,
# instead of a fresh python subprocess per repo lookup. Service names (the
# JSON keys here) are always plain identifiers - see SERVICES above - so no
# sanitizing is needed before using one as a shell variable name suffix.
eval "$(python3 -c '
import json, sys
for name, url in json.loads(sys.argv[1]).items():
    print("REPO_URL_" + name + "=" + url)
' "${REPO_URLS_JSON}")"

REGISTRY="${REPO_URL_api%%/*}"

echo "== pushing images for ${ENVIRONMENT}, tag ${IMAGE_TAG} =="

aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

for service in "${SERVICES[@]}"; do
  repo_url_var="REPO_URL_${service}"
  repo_url="${!repo_url_var}"
  echo "-- ${service}: ${repo_url}:${IMAGE_TAG}"
  if [[ "${service}" == "grafana" ]]; then
    docker build -f docker/grafana/Dockerfile -t "${repo_url}:${IMAGE_TAG}" .
  else
    docker build -f docker/Dockerfile --build-arg SERVICE="${service}" -t "${repo_url}:${IMAGE_TAG}" .
  fi
  docker push "${repo_url}:${IMAGE_TAG}"
done

echo "== done =="
echo "Deploy with: terraform -chdir=${TF_DIR} apply -var image_tag=${IMAGE_TAG}"
