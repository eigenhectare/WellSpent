#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <support-site-repository> <new-sanitized-report-directory>" >&2
    exit 64
fi

site_root="$1"
report_directory="$2"
fail() { echo "WellSpent support-site check failed: $1" >&2; exit 1; }

[[ -d "${site_root}/.git" ]] || fail 'support-site Git repository is missing'
site_root="$(cd "${site_root}" && pwd -P)"
readonly site_root
[[ ! -e "${report_directory}" ]] || fail 'report directory already exists; preserve earlier evidence'
report_parent="$(cd "$(dirname "${report_directory}")" && pwd -P)" \
    || fail 'report parent must already exist'
report_directory="${report_parent}/$(basename "${report_directory}")"
readonly report_directory
case "${report_directory}/" in "${site_root}/"*) fail 'report must be outside the support-site repository' ;; esac

[[ -z "$(git -C "${site_root}" status --porcelain=v1)" ]] || fail 'support-site checkout is dirty'
readonly source_commit="$(git -C "${site_root}" rev-parse HEAD)"
readonly source_tree="$(git -C "${site_root}" rev-parse HEAD^{tree})"
[[ "${source_commit}" =~ ^[0-9a-f]{40}$ && "${source_tree}" =~ ^[0-9a-f]{40}$ ]] \
    || fail 'invalid support-site source identity'

required_files=(
    index.html
    privacy/index.html
    support/index.html
    styles.css
    favicon.svg
    robots.txt
    sitemap.xml
)
for relative in "${required_files[@]}"; do
    [[ -s "${site_root}/${relative}" ]] || fail "missing ${relative}"
done
xmllint --noout "${site_root}/favicon.svg" || fail 'favicon SVG is malformed'

html_pages=(index.html privacy/index.html support/index.html)
for relative in "${html_pages[@]}"; do
    page="${site_root}/${relative}"
    [[ "$(rg -c -F '<!doctype html>' "${page}")" == 1 ]] || fail "${relative} doctype"
    [[ "$(rg -c -F '<html lang="en">' "${page}")" == 1 ]] || fail "${relative} language"
    [[ "$(rg -c -F '<meta name="viewport" content="width=device-width, initial-scale=1">' "${page}")" == 1 ]] \
        || fail "${relative} viewport"
    [[ "$(rg -c 'rel="canonical" href="https://wellspent-holdings\.github\.io/(support/|privacy/)?"' "${page}")" == 1 ]] \
        || fail "${relative} canonical URL"
    [[ "$(rg -c -F 'href="https://wellspent-holdings.github.io/styles.css"' "${page}")" == 1 ]] \
        || fail "${relative} stylesheet"
    [[ "$(rg -c -F 'href="/support/"' "${page}")" -ge 1 ]] || fail "${relative} support link"
    [[ "$(rg -c -F 'href="/privacy/"' "${page}")" -ge 1 ]] || fail "${relative} privacy link"
    [[ "$(rg -c -F 'src="/favicon.svg"' "${page}")" == 1 ]] || fail "${relative} favicon"
    rg -q -F 'iPhone and Apple Watch' "${page}" || fail "${relative} paired-product disclosure"
    rg -q -F 'wellspent_support@pm.me' "${page}" || fail "${relative} public support contact"
done

if rg -q -F 'stays on this iPhone' "${site_root}/index.html" "${site_root}/privacy/index.html" "${site_root}/support/index.html"; then
    fail 'obsolete iPhone-only retention claim'
fi
if rg -q -F 'does not request Calendar or notification access' "${site_root}/privacy/index.html"; then
    fail 'obsolete notification-access claim'
fi

require_text() {
    local file="$1" text="$2"
    rg -q -F "${text}" "${site_root}/${file}" || fail "${file} is missing: ${text}"
}

require_text index.html 'Your iPhone and paired Apple Watch exchange only the local ledger information needed for the companion experience.'
require_text index.html 'No account. No ads. No analytics. No tracking.'
require_text privacy/index.html 'WellSpent does not collect data from the app.'
require_text privacy/index.html 'through Apple&#x27;s Watch Connectivity'
require_text privacy/index.html 'Unsynchronized Watch changes are device-local'
require_text privacy/index.html 'Deleting or erasing one companion is not a remote erase of the other device.'
require_text privacy/index.html 'does not register for Apple Push Notification service'
require_text support/index.html 'How do I set up the Apple Watch app?'
require_text support/index.html 'Why does the Watch show Pending?'
require_text support/index.html 'What does Review Required mean?'
require_text support/index.html 'Do not rely on backup or restore to recover it'
require_text support/index.html 'Never include confidential client names, notes, work records, personal notifications, or account details.'

readonly faq_count="$(rg -o '<details>' "${site_root}/support/index.html" | wc -l | tr -d ' ')"
[[ "${faq_count}" -ge 10 ]] || fail 'support page does not contain the complete Watch-aware FAQ set'

scratch_manifest="$(mktemp "${TMPDIR:-/tmp}/WellSpentSupportSiteManifest.XXXXXX")"
cleanup() { rm -f -- "${scratch_manifest}"; }
trap cleanup EXIT
(
    cd "${site_root}"
    for relative in "${required_files[@]}"; do
        shasum -a 256 "${relative}"
    done
) >"${scratch_manifest}"
readonly file_manifest_sha256="$(shasum -a 256 "${scratch_manifest}" | awk '{print $1}')"
readonly observed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "${report_directory}"
jq -n \
    --arg observedAt "${observed_at}" \
    --arg sourceCommit "${source_commit}" \
    --arg sourceTree "${source_tree}" \
    --arg fileManifestSHA256 "${file_manifest_sha256}" \
    --argjson faqCount "${faq_count}" \
    '{
        schemaVersion:1,
        observedAt:$observedAt,
        rawIdentifiersRetained:false,
        inspection:"passed",
        publicationPerformed:false,
        source:{commit:$sourceCommit,tree:$sourceTree},
        filesChecked:7,
        htmlPagesChecked:3,
        faqCount:$faqCount,
        localLinksChecked:true,
        pairedProductCopyChecked:true,
        privacyRetentionCopyChecked:true,
        fileManifestSHA256:$fileManifestSHA256,
        remaining:["publish authorized commit", "verify live pages and links"]
    }' >"${report_directory}/summary.json"

echo "WellSpent support-site source passed. Nothing was published. Sanitized evidence: ${report_directory}/summary.json"
