#!/bin/bash
#
# az-failure-drill.sh <az-index: 0|1>
#
# Chaos drill: simulates one AZ going down for api and checker - the two
# services that actually run redundantly across both AZs in prod
# (desired_count = 2, terraform/environments/prod/main.tf). prod-only on
# purpose: dev runs a single task per service with no AZ redundancy to prove
# anything about, and this drill's whole point is proving the redundancy
# prod pays for actually works, not just exists in Terraform.
#
# Stopping the AZ's current tasks alone isn't a real AZ-failure simulation -
# ECS would just reschedule replacements right back into the "failed" AZ,
# since nothing told it not to. This script also temporarily removes that
# AZ's subnet from each service's network_configuration, so new/replacement
# tasks can only land in the surviving AZ - the same effect an actual subnet-
# level AZ outage would have on task placement.
#
# Expect: the ALB keeps serving throughout (api's surviving-AZ task(s) pick
# up all traffic), and running task counts recover to desired_count - now
# entirely within the surviving AZ - within a couple of minutes. Watch:
#   aws ecs describe-services --cluster <cluster> --services <service> --query 'services[0].{running:runningCount,desired:desiredCount}'
# and the ALB target health / dashboard from Phase 8. This script does not
# restore the network configuration for you - see the end of its output.

set -euo pipefail

AZ_INDEX="${1:?Usage: az-failure-drill.sh <az-index: 0|1>}"
if [[ "${AZ_INDEX}" != "0" && "${AZ_INDEX}" != "1" ]]; then
  echo "az-index must be 0 or 1 (index into private_subnet_ids)." >&2
  exit 1
fi

TF_DIR="terraform/environments/prod"

echo "This will simulate an AZ failure in PRODUCTION (api + checker)."
read -rp "Type the environment name to confirm: " confirm
[[ "${confirm}" == "prod" ]] || { echo "Aborted."; exit 1; }

CLUSTER="$(terraform -chdir="${TF_DIR}" output -raw ecs_cluster_name)"
SUBNETS_JSON="$(terraform -chdir="${TF_DIR}" output -json private_subnet_ids)"
SG_IDS_JSON="$(terraform -chdir="${TF_DIR}" output -json security_group_ids)"
SERVICE_NAMES_JSON="$(terraform -chdir="${TF_DIR}" output -json ecs_service_names)"

FAILED_SUBNET="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])[int(sys.argv[2])])" "${SUBNETS_JSON}" "${AZ_INDEX}")"
SURVIVING_SUBNET="$(python3 -c "import json,sys; s=json.loads(sys.argv[1]); print(s[1-int(sys.argv[2])])" "${SUBNETS_JSON}" "${AZ_INDEX}")"

echo "== failing subnet ${FAILED_SUBNET}, surviving subnet ${SURVIVING_SUBNET} =="

for service_key in api checker; do
  ECS_SERVICE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['${service_key}'])" "${SERVICE_NAMES_JSON}")"
  SG_ID="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['${service_key}'])" "${SG_IDS_JSON}")"

  echo "-- ${ECS_SERVICE}: restricting placement to ${SURVIVING_SUBNET} only --"
  aws ecs update-service --cluster "${CLUSTER}" --service "${ECS_SERVICE}" \
    --network-configuration "awsvpcConfiguration={subnets=[${SURVIVING_SUBNET}],securityGroups=[${SG_ID}],assignPublicIp=DISABLED}" \
    >/dev/null

  echo "-- ${ECS_SERVICE}: stopping any tasks currently in ${FAILED_SUBNET} --"
  TASK_ARNS_JSON="$(aws ecs list-tasks --cluster "${CLUSTER}" --service-name "${ECS_SERVICE}" --query 'taskArns' --output json)"
  if [[ "${TASK_ARNS_JSON}" != "[]" ]]; then
    # --tasks takes one ARN per argument, not one space-joined string - a bash
    # array (not a plain quoted variable) is what keeps them separate here.
    # Built with a read loop, not `mapfile` (bash 4+ only - macOS ships 3.2
    # as /bin/bash, which this script's shebang resolves to).
    TASK_ARNS=()
    while IFS= read -r arn; do
      TASK_ARNS+=("${arn}")
    done < <(echo "${TASK_ARNS_JSON}" | python3 -c "import json,sys; print('\n'.join(json.load(sys.stdin)))")
    aws ecs describe-tasks --cluster "${CLUSTER}" --tasks "${TASK_ARNS[@]}" \
      --query 'tasks[]' --output json \
      | python3 -c "
import json, sys
tasks = json.load(sys.stdin)
failed_subnet = sys.argv[1]
for task in tasks:
    details = task.get('attachments', [{}])[0].get('details', [])
    subnet_id = next((d['value'] for d in details if d['name'] == 'subnetId'), None)
    if subnet_id == failed_subnet:
        print(task['taskArn'])
" "${FAILED_SUBNET}" \
      | while read -r task_arn; do
          echo "   stopping ${task_arn}"
          aws ecs stop-task --cluster "${CLUSTER}" --task "${task_arn}" --reason "az-failure-drill" >/dev/null
        done
  fi
done

cat <<EOF

Triggered for api and checker. Watch, don't just wait:
  aws ecs describe-services --cluster ${CLUSTER} --services <service> --query 'services[0].{running:runningCount,desired:desiredCount}'
  ALB target health / the dashboard from terraform/modules/observability

When you're done observing, restore both subnets via Terraform (not
hardcoded here, so it can't drift from what environments/prod/main.tf
actually says):
  terraform -chdir=${TF_DIR} apply -var image_tag=<current tag>
EOF
