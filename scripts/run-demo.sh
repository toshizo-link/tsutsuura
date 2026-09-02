#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"

default_runtime_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"
runtime_version="${TSUTSUURA_RUNTIME_VERSION:-${default_runtime_version}}"
device_name="${TSUTSUURA_DEVICE_NAME:-iPhone 17 Pro Max}"
demo_mode="${TSUTSUURA_DEMO_MODE:-authenticated}"
derived_data_path="${TSUTSUURA_DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/tsutsuura-demo-derived-data}"
project_path="${repository_root}/tsutsuura/tsutsuura.xcodeproj"
bundle_identifier="toshizo.link.tsutsuura"

case "${demo_mode}" in
    authenticated|signedOut) ;;
    *)
        echo "TSUTSUURA_DEMO_MODE must be authenticated or signedOut." >&2
        exit 64
        ;;
esac

runtime_identifier="$(
    xcrun simctl list runtimes \
        | sed -nE "s/.*iOS ${runtime_version} .* - (com\\.apple\\.CoreSimulator\\.SimRuntime\\.iOS-[^ ]+).*/\\1/p" \
        | head -n 1
)"

if [[ -z "${runtime_identifier}" ]]; then
    cat >&2 <<EOF
iOS ${runtime_version} Simulator is not installed.
Install the matching arm64 runtime first:

  xcodebuild -downloadPlatform iOS -architectureVariant arm64
EOF
    exit 69
fi

destinations="$(
    xcodebuild \
        -project "${project_path}" \
        -scheme tsutsuura \
        -showdestinations 2>&1 \
        || true
)"

# Resolve the device from Xcode's eligible destinations rather than taking the
# first same-version simctl device, which may belong to an older runtime patch.
device_udid="$(
    while IFS= read -r destination; do
        if [[ "${destination}" == *"platform:iOS Simulator"* ]] \
            && [[ "${destination}" == *"OS:${runtime_version}"* ]] \
            && [[ "${destination}" == *"name:${device_name} }"* ]]; then
            sed -nE 's/.*id:([^,}]+).*/\1/p' <<<"${destination}" \
                | tr -d ' '
            break
        fi
    done <<<"${destinations}"
)"

if [[ -z "${device_udid}" ]]; then
    device_type_identifier="$(
        xcrun simctl list devicetypes \
            | grep -F "${device_name} (" \
            | sed -nE 's/.*\((com\.apple\.CoreSimulator\.SimDeviceType\.[^)]+)\)$/\1/p' \
            | head -n 1
    )"
    if [[ -z "${device_type_identifier}" ]]; then
        echo "Simulator device type '${device_name}' is unavailable." >&2
        exit 69
    fi
    device_udid="$(
        xcrun simctl create \
            "${device_name}" \
            "${device_type_identifier}" \
            "${runtime_identifier}"
    )"
    destinations="$(
        xcodebuild \
            -project "${project_path}" \
            -scheme tsutsuura \
            -showdestinations 2>&1 \
            || true
    )"
fi

if ! grep -Fq "${device_udid}" <<<"${destinations}"; then
    cat >&2 <<EOF
The installed iOS ${runtime_version} runtime is not compatible with this
Xcode simulator SDK. Install Xcode's currently recommended runtime patch:

  xcodebuild -downloadPlatform iOS -architectureVariant arm64
EOF
    exit 69
fi

xcrun simctl boot "${device_udid}" 2>/dev/null || true
xcrun simctl bootstatus "${device_udid}" -b

xcodebuild \
    -project "${project_path}" \
    -scheme tsutsuura \
    -configuration Debug \
    -destination "id=${device_udid}" \
    -derivedDataPath "${derived_data_path}" \
    CODE_SIGNING_ALLOWED=NO \
    build

application_path="${derived_data_path}/Build/Products/Debug-iphonesimulator/tsutsuura.app"
if [[ ! -d "${application_path}" ]]; then
    echo "Built application was not found at ${application_path}." >&2
    exit 66
fi

xcrun simctl install "${device_udid}" "${application_path}"
xcrun simctl terminate "${device_udid}" "${bundle_identifier}" 2>/dev/null || true
SIMCTL_CHILD_TSUTSUURA_DEMO_MODE="${demo_mode}" \
SIMCTL_CHILD_UI_TESTING="1" \
    xcrun simctl launch "${device_udid}" "${bundle_identifier}"

open -a Simulator

echo
echo "Launched tsutsuura in '${demo_mode}' demo mode on ${device_name} (${device_udid})."
