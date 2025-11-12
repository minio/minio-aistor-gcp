#!/bin/bash
#
# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eox pipefail

# This is the entry point for the test deployment

# If any command returns with non-zero exit code, set -e will cause the script
# to exit. Prior to exit, set App assembly status to "Failed".
handle_failure() {
  code=$?
  if [[ -z "$NAME" ]] || [[ -z "$NAMESPACE" ]]; then
    # /bin/expand_config.py might have failed.
    # We fall back to the unexpanded params to get the name and namespace.
    NAME="$(/bin/print_config.py \
            --xtype NAME \
            --values_mode raw)"
    NAMESPACE="$(/bin/print_config.py \
            --xtype NAMESPACE \
            --values_mode raw)"
    export NAME
    export NAMESPACE
  fi
  patch_assembly_phase.sh --status="Failed"
  exit $code
}
trap "handle_failure" EXIT

test_schema="/data-test/schema.yaml"
overlay_test_schema.py \
  --test_schema "$test_schema" \
  --original_schema "/data/schema.yaml" \
  --output "/data/schema.yaml" \
  | awk '{print "SMOKE_TEST "$0}'

NAME="$(/bin/print_config.py \
    --xtype NAME \
    --values_mode raw)"
NAMESPACE="$(/bin/print_config.py \
    --xtype NAMESPACE \
    --values_mode raw)"
export NAME
export NAMESPACE

echo "Deploying application \"$NAME\" in test mode"

app_uid=$(kubectl get "applications.app.k8s.io/$NAME" \
  --namespace="$NAMESPACE" \
  --output=jsonpath='{.metadata.uid}')
app_api_version=$(kubectl get "applications.app.k8s.io/$NAME" \
  --namespace="$NAMESPACE" \
  --output=jsonpath='{.apiVersion}')
namespace_uid=$(kubectl get "namespaces/$NAMESPACE" \
  --output=jsonpath='{.metadata.uid}')

/bin/expand_config.py --values_mode raw --app_uid "$app_uid"

# Note: Pool normalization (dictionary to array) is now handled in Helm templates
# via the "minio-aistor.normalizePools" helper function in _helpers.tpl

create_manifests.sh --mode="test"

# Assign owner references for the resources.
/bin/set_ownership.py \
  --app_name "$NAME" \
  --app_uid "$app_uid" \
  --app_api_version "$app_api_version" \
  --namespace "$NAMESPACE" \
  --namespace_uid "$namespace_uid" \
  --manifests "/data/manifest-expanded" \
  --dest "/data/resources.yaml"

validate_app_resource.py --manifests "/data/resources.yaml"

separate_tester_resources.py \
  --app_uid "$app_uid" \
  --app_name "$NAME" \
  --app_api_version "$app_api_version" \
  --manifests "/data/resources.yaml" \
  --out_manifests "/data/resources.yaml" \
  --out_test_manifests "/data/tester.yaml"

# Split resources into CRDs and non-CRDs to handle race condition
# Apply CRDs first, wait for them to be established, then apply custom resources
echo "Splitting resources into CRDs and application resources..."
cat /data/resources.yaml | python3 -c '
import sys
import yaml

docs = list(yaml.safe_load_all(sys.stdin))
crds = [d for d in docs if d and d.get("kind") == "CustomResourceDefinition"]
non_crds = [d for d in docs if d and d.get("kind") != "CustomResourceDefinition"]

with open("/data/crds.yaml", "w") as f:
    yaml.dump_all(crds, f)

with open("/data/non-crds.yaml", "w") as f:
    yaml.dump_all(non_crds, f)
'

# Apply CRDs first
echo "Applying CRDs..."
kubectl apply --filename="/data/crds.yaml"

# Wait for CRDs to be established before proceeding
echo "Waiting for CRDs to be established..."
kubectl wait --for condition=established --timeout=60s \
  crd/objectstores.aistor.min.io \
  crd/adminjobs.aistor.min.io \
  crd/policybindings.sts.min.io 2>/dev/null || true

# Give the API server a moment to fully register the CRDs
echo "Sleeping 5 seconds for API server to register CRDs..."
sleep 5

# Now apply all other resources including custom resources
echo "Applying application resources..."
kubectl apply --namespace="$NAMESPACE" --filename="/data/non-crds.yaml"

patch_assembly_phase.sh --status="Success"

wait_for_ready.py \
  --name $NAME \
  --namespace $NAMESPACE \
  --timeout ${WAIT_FOR_READY_TIMEOUT:-300}

tester_manifest="/data/tester.yaml"
if [[ -e "$tester_manifest" ]]; then
  cat $tester_manifest

  run_tester.py \
    --namespace $NAMESPACE \
    --manifest $tester_manifest \
    --timeout ${TESTER_TIMEOUT:-300} \
    | awk '{print "SMOKE_TEST "$0}'
else
  echo "SMOKE_TEST No tester manifest found at $tester_manifest."
fi

clean_iam_resources.sh

trap - EXIT
