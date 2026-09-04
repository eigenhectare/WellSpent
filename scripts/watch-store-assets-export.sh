#!/bin/bash
set -euo pipefail
readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly result_bundle="${1:?draft screenshot result bundle required}"
readonly output_directory="${2:?new output directory required}"
[[ ! -e "${output_directory}" ]] || { echo 'Use a new draft directory; preserve existing assets.' >&2; exit 1; }
bash "${script_directory}/ci-check-results.sh" "${result_bundle}" 1
mkdir -p "${output_directory}"
xcrun xcresulttool export attachments --path "${result_bundle}" --output-path "${output_directory}/raw" \
    > "${output_directory}/export.log" 2>&1
assets=()
common_size=''
for screen in 01-projects 02-goal-setup 03-active-metrics 04-controls 05-summary; do
    exported="$(jq -er --arg prefix "DRAFT-WAT27-${screen}_" '
        [.[] | select(.testIdentifier == "WatchStoreAssetDraftUITests/testCaptureFiveDraftStoreScreens()")
        | .attachments[] | select((.suggestedHumanReadableName | startswith($prefix))
            and (.suggestedHumanReadableName | endswith(".png"))) | .exportedFileName]
        | if length == 1 then .[0] else error("Expected exactly one draft screenshot per screen") end
    ' "${output_directory}/raw/manifest.json")"
    [[ "${exported}" =~ ^[A-Za-z0-9_-]+\.png$ ]] || exit 1
    asset="${output_directory}/DRAFT-${screen}.png"
    cp "${output_directory}/raw/${exported}" "${asset}"
    dimensions="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "${asset}")"
    width="$(awk '$1 == "pixelWidth:" {print $2}' <<< "${dimensions}")"
    height="$(awk '$1 == "pixelHeight:" {print $2}' <<< "${dimensions}")"
    [[ "$(awk '$1 == "hasAlpha:" {print $2}' <<< "${dimensions}")" == no ]] || exit 1
    case "${width}x${height}" in 422x514|410x502|416x496|396x484|368x448|312x390) ;; *) exit 1 ;; esac
    [[ -z "${common_size}" || "${common_size}" == "${width}x${height}" ]] || exit 1
    common_size="${width}x${height}"
    digest="$(shasum -a 256 "${asset}" | awk '{print $1}')"
    jq -n --arg file "DRAFT-${screen}.png" --arg digest "${digest}" --argjson width "${width}" --argjson height "${height}" \
        '{file:$file,sha256:$digest,width:$width,height:$height}' > "${output_directory}/${screen}.json"
    assets+=("${output_directory}/${screen}.json")
done
jq -s '{schemaVersion:1,draftOnly:true,releaseCandidate:false,
    source:"Unmodified native screenshots from isolated DEBUG Simulator fixtures; fictitious data.",
    requirementCheckedOn:"2026-09-03",assets:.}' "${assets[@]}" > "${output_directory}/manifest.json"
echo "Five native-size, opaque draft screenshots exported: ${output_directory}"
