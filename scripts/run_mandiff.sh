#!/bin/bash

# Copyright 2019 Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

WD=$(dirname "$0")
WD=$(cd "$WD"; pwd)
ROOT=$(dirname "$WD")
OUT=${OUT:-/tmp/istio-mandiff-out}
CHARTS_DIR="${GOPATH}/src/istio.io/installer"
rm -Rf "${OUT}/*"
mkdir -p "${OUT}"

ISTIO_SYSTEM_NS=${ISTIO_SYSTEM_NS:-istio-system}
ISTIO_RELEASE=${ISTIO_RELEASE:-istio}
ISTIO_DEFAULT_PROFILE=${ISTIO_DEFAULT_PROFILE:-default}
ISTIO_DEMO_PROFILE=${ISTIO_DEMO_PROFILE:-demo}
ISTIO_DEMOAUTH_PROFILE=${ISTIO_DEMOAUTH_PROFILE:-"demo-auth"}
ISTIO_MINIMAL_PROFILE=${ISTIO_MINIMAL_PROFILE:-minimal}
ISTIO_SDS_PROFILE=${ISTIO_SDS_PROFILE:-sds}\

# declare map with profile as key and charts as values
declare -A PROFILE_CHARTS_MAP
PROFILE_CHARTS_MAP["${ISTIO_DEFAULT_PROFILE}"]="crds istio-control/istio-discovery istio-control/istio-config istio-control/istio-autoinject gateways/istio-ingress istio-telemetry/mixer-telemetry istio-policy security/citadel"
PROFILE_CHARTS_MAP["${ISTIO_DEMO_PROFILE}"]="crds istio-control/istio-discovery istio-control/istio-config istio-control/istio-autoinject gateways/istio-ingress gateways/istio-egress istio-telemetry/mixer-telemetry istio-policy security/citadel"
PROFILE_CHARTS_MAP["${ISTIO_DEMOAUTH_PROFILE}"]="crds istio-control/istio-discovery istio-control/istio-config istio-control/istio-autoinject gateways/istio-ingress gateways/istio-egress istio-telemetry/mixer-telemetry istio-policy security/citadel"
PROFILE_CHARTS_MAP["${ISTIO_MINIMAL_PROFILE}"]="crds istio-control/istio-discovery"
PROFILE_CHARTS_MAP["${ISTIO_SDS_PROFILE}"]="crds istio-control/istio-discovery istio-control/istio-config istio-control/istio-autoinject gateways/istio-ingress istio-telemetry/mixer-telemetry istio-policy security/citadel security/nodeagent"

# declare map with profile as key and charts as values
declare -A NAMESPACES_MAP
NAMESPACES_MAP["crds"]="istio-system"
NAMESPACES_MAP["istio-control/istio-discovery"]="istio-system"
NAMESPACES_MAP["istio-control/istio-config"]="istio-system"
NAMESPACES_MAP["istio-control/istio-autoinject"]="istio-system"
NAMESPACES_MAP["gateways/istio-ingress"]="istio-system"
NAMESPACES_MAP["gateways/istio-egress"]="istio-system"
NAMESPACES_MAP["istio-telemetry/mixer-telemetry"]="istio-system"
NAMESPACES_MAP["istio-policy"]="istio-system"
NAMESPACES_MAP["security/citadel"]="istio-system"
NAMESPACES_MAP["security/nodeagent"]="istio-system"

# define the ingored resource list for manifest comparison
MANDIFF_IGNORE_RESOURCE_LIST="ConfigMap::istio,ConfigMap::istio-sidecar-injector"

# No unset vars, print commands as they're executed, and exit on any non-zero
# return code
set -u
set -x
set -e

cd "${ROOT}"

export GO111MODULE=on
# build the istio operator binary
go build -o "${GOPATH}/bin/mesh" ./cmd/mesh.go

# download the helm binary
${ROOT}/bin/init_helm.sh

# render all the templates with helm template.
function helm_manifest() {
    local namespace="${1}"
    local release="${2}"
    local chart="${3}"
    local profile="${4}"

    # the global settings are the default for the chart
    # the specified profile will override the gloal settings
    local cfg="-f ${chart}/global.yaml -f ${ROOT}/tests/profiles/helm/values-istio-${profile}.yaml"

    # create parent directory for the manifests rendered by helm template
    local out_dir="${OUT}/helm-template/istio-${profile}"
    mkdir -p "${out_dir}"

    local charts="${PROFILE_CHARTS_MAP[${profile}]}"
    for c in $(echo $charts | tr " " "\n")
    do
       echo "Rendering ${c}"
       mkdir -p "${out_dir}/${c}"
       helm template --namespace "${NAMESPACES_MAP[${c}]}" --name "${release}" "${chart}/${c}" ${cfg} > "${out_dir}/${c}.yaml"
    done
 #   cat $(find "${out_dir}" -name '*.yaml') > "${out_dir}/combined.yaml"
}

# render all the templates with mesh manifest.
function mesh_manifest() {
    local profile="${1}"
    local out_dir="${OUT}/mesh-manifest/istio-${profile}"
    mkdir -p "${out_dir}"
    mesh manifest generate --filename "${ROOT}/data/profiles/${profile}.yaml" --dry-run=false --output "${out_dir}" 2>&1
#    cat $(find "${out_dir}" -name "*.yaml") > "${out_dir}/combined.yaml"
}

# compare the manifests generated by the helm template and mesh manifest
function mesh_mandiff_with_profile() {
    local profile="${1}"

    helm_manifest ${ISTIO_SYSTEM_NS} ${ISTIO_RELEASE} ${CHARTS_DIR} ${profile}
    mesh_manifest ${profile}

    mesh manifest diff --ignore "${MANDIFF_IGNORE_RESOURCE_LIST}" --directory "${OUT}/helm-template/istio-${profile}" "${OUT}/mesh-manifest/istio-${profile}"
}

mesh_mandiff_with_profile "${ISTIO_DEFAULT_PROFILE}" > "${OUT}/mandiff-default-profile.diff" || echo "default profile has diffs"
mesh_mandiff_with_profile "${ISTIO_DEMO_PROFILE}" > "${OUT/}mandiff-demo-profile.diff" || echo "default profile has diffs"
mesh_mandiff_with_profile "${ISTIO_DEMOAUTH_PROFILE}" > "${OUT}/mandiff-demoauth-profile.diff" || echo "default profile has diffs"
mesh_mandiff_with_profile "${ISTIO_MINIMAL_PROFILE}" > "${OUT}/mandiff-minimal-profile.diff" || echo "default profile has diffs"
mesh_mandiff_with_profile "${ISTIO_SDS_PROFILE}" > "${OUT}/mandiff-sds-profile.diff" || echo "default profile has diffs"

