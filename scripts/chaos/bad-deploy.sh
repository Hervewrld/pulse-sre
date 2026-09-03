#!/bin/bash
#
# bad-deploy.sh <dev|prod> <api|scheduler|checker>
#
# Chaos drill: registers a new task definition revision for one service that
# points at a nonexistent image tag, then forces the service to deploy it -
# to prove terraform/modules/ecs_service's deployment circuit breaker
# actually rolls back a bad deploy, instead of existing in Terraform as an
# untested feature nobody has watched fire. Goes through the ECS API
# directly, on purpose - this is testing ECS's own circuit breaker, not
# .github/workflows/deploy.yml's plan/apply pipeline (that path already gets
# exercised by every normal deploy).
#
# Expect: ECS can't pull the (nonexistent) image, the new tasks never reach
# RUNNING, and the circuit breaker rolls the service back on its own within
# a few minutes - no restore step needed for the *service*. Terraform's
# state still expects the task definition revision from before this script
# ran, though: after the drill, reconcile it with a normal apply (see below).

set -euo pipefail

ENVIRONMENT="${1:?Usage: bad-deploy.sh <dev|prod> <api|scheduler|checker>}"
SERVICE="${2:?Usage: bad-deploy.sh <dev|prod> <api|scheduler|checker>}"
TF_DIR="terraform/environments/${ENVIRONMENT}"

if [[ "${ENVIRONMENT}" == "prod" ]]; then
  echo "This will deliberately break ${SERVICE} in PRODUCTION."
  read -rp "Type the environment name to confirm: " confirm
  [[ "${confirm}" == "prod" ]] || { echo "Aborted."; exit 1; }
fi

CLUSTER="$(terraform -chdir="${TF_DIR}" output -raw ecs_cluster_name)"
ECS_SERVICE="$(terraform -chdir="${TF_DIR}" output -json ecs_service_names \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['${SERVICE}'])")"
CURRENT_TD="$(aws ecs describe-services --cluster "${CLUSTER}" --services "${ECS_SERVICE}" \
  --query 'services[0].taskDefinition' --output text)"

echo "== registering a broken revision of ${CURRENT_TD} (nonexistent image tag) =="
BROKEN_TD_JSON="$(aws ecs describe-task-definition --task-definition "${CURRENT_TD}" --query 'taskDefinition' \
  | python3 -c "
import json, sys
td = json.load(sys.stdin)
for key in ('taskDefinitionArn', 'revision', 'status', 'requiresAttributes', 'compatibilities', 'registeredAt', 'registeredBy'):
    td.pop(key, None)
td['containerDefinitions'][0]['image'] = td['containerDefinitions'][0]['image'].rsplit(':', 1)[0] + ':chaos-drill-nonexistent-tag'
print(json.dumps(td))
")"
NEW_TD_ARN="$(aws ecs register-task-definition --cli-input-json "${BROKEN_TD_JSON}" \
  --query 'taskDefinition.taskDefinitionArn' --output text)"

echo "== forcing ${ECS_SERVICE} to deploy it =="
aws ecs update-service --cluster "${CLUSTER}" --service "${ECS_SERVICE}" --task-definition "${NEW_TD_ARN}" >/dev/null

cat <<EOF

Triggered. Watch, don't just wait:
  aws ecs describe-services --cluster ${CLUSTER} --services ${ECS_SERVICE} --query 'services[0].deployments'
  CloudWatch alarms: pulse-${ENVIRONMENT}-ecs_${SERVICE}_cpu_high / _memory_high

Once ECS has rolled the service back on its own (deployments shows one
PRIMARY entry again, back on ${CURRENT_TD}), reconcile Terraform's state
with what's actually running:
  terraform -chdir=${TF_DIR} plan -var image_tag=<last known-good tag>
EOF
