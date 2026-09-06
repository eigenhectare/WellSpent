#!/bin/bash
set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly filter="${script_directory}/watch-distribution-icon-check.jq"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/WellSpentDistributionIcons.XXXXXX")"
readonly fixture_root
cleanup() {
    [[ -n "${fixture_root}" && -d "${fixture_root}" ]] || return
    rm -rf -- "${fixture_root}"
}
trap cleanup EXIT

jq -n '
    {Name:"AppIcon",AssetType:"Icon Image",RenditionName:"AppIcon.png",
     Opaque:true,PixelWidth:1024,PixelHeight:1024,Colorspace:"srgb",ColorModel:"RGB",
     BitsPerComponent:8,Scale:1,Idiom:"phone",SHA1Digest:("A" * 64)} as $default
    | [$default,
       ($default + {Appearance:"UIAppearanceDark",RenditionName:"AppIcon-Dark.png",SHA1Digest:("B" * 64)}),
       {Name:"AppIcon",AssetType:"MultiSized Image",Idiom:"phone"},
       {Name:"UnrelatedImage",AssetType:"Image"}]
' >"${fixture_root}/phone.json"
jq '[.[0] | .Idiom = "watch"] + [{Name:"AppIcon",AssetType:"MultiSized Image",Idiom:"watch"}]' \
    "${fixture_root}/phone.json" >"${fixture_root}/watch.json"

check() {
    jq -e --arg component "$1" -f "${filter}" "$2" >"${fixture_root}/result.json"
}

check phone "${fixture_root}/phone.json"
jq -e '.compiledIconChecked and .compiledIconRenditionDigest == ("A" * 64)
    and (.compiledIconRenditions | map(.appearance)) == ["default","dark"]
    and .compiledIconRenditions[1] == {
        appearance:"dark",renditionName:"AppIcon-Dark.png",digest:("B" * 64),idiom:"phone",
        pixelWidth:1024,pixelHeight:1024,opaque:true,colorModel:"RGB",colorspace:"srgb",
        bitsPerComponent:8,scale:1
    }' "${fixture_root}/result.json" >/dev/null
check watch "${fixture_root}/watch.json"
jq -e '.compiledIconChecked and .compiledIconRenditionDigest == ("A" * 64)
    and (.compiledIconRenditions | map(.appearance)) == ["default"]' \
    "${fixture_root}/result.json" >/dev/null
jq 'reverse' "${fixture_root}/phone.json" >"${fixture_root}/reversed.json"
check phone "${fixture_root}/reversed.json"
jq -e '.compiledIconRenditionDigest == ("A" * 64)
    and (.compiledIconRenditions | map(.appearance)) == ["default","dark"]' \
    "${fixture_root}/result.json" >/dev/null

rejected=0
expect_rejection() {
    local component="$1" source="$2" mutation="$3" label="$4"
    jq "${mutation}" "${fixture_root}/${source}.json" >"${fixture_root}/invalid.json"
    if check "${component}" "${fixture_root}/invalid.json" 2>"${fixture_root}/error.log"; then
        echo "Distribution icon guard accepted invalid fixture: ${label}" >&2
        exit 1
    fi
    rejected=$((rejected + 1))
}

expect_rejection phone phone 'del(.[0])' 'missing default'
expect_rejection phone phone 'del(.[1])' 'missing dark'
expect_rejection phone phone '. + [.[0]]' 'duplicate default'
expect_rejection phone phone '. + [.[1]]' 'duplicate dark'
expect_rejection phone phone '.[1] = .[0]' 'two defaults replacing dark'
expect_rejection phone phone '. + [(.[1] | .Appearance = "UIAppearanceTinted")]' 'unexpected extra appearance'
expect_rejection phone phone '.[1].Appearance = "UIAppearanceTinted"' 'unexpected dark replacement'
expect_rejection phone phone '.[0].Appearance = null' 'null default appearance'
expect_rejection phone phone '.[0].Appearance = ""' 'empty default appearance'
expect_rejection phone phone '.[0].Appearance = "UIAppearanceLight"' 'explicit undeclared light appearance'
expect_rejection watch phone 'map(if .Idiom == "phone" then .Idiom = "watch" else . end)' 'dark Watch rendition'
expect_rejection watch watch '. + [.[0]]' 'duplicate Watch default'
expect_rejection watch watch 'del(.[0])' 'missing Watch default'
expect_rejection unknown watch '.' 'unsupported component'
expect_rejection phone phone '{assets:.}' 'non-array inventory'
expect_rejection phone phone '. + [null]' 'non-object inventory entry'

# Mutate each actual rendition, not only the first, so a valid default cannot
# mask an invalid dark image. Require every field rather than accepting nulls.
for index in 0 1; do
    for mutation in \
        'Opaque=false' 'Opaque="true"' 'PixelWidth=1023' 'PixelHeight=1023' \
        'PixelWidth="1024"' 'PixelHeight="1024"' 'Colorspace="displayP3"' \
        'ColorModel="Monochrome"' 'BitsPerComponent=16' 'BitsPerComponent="8"' \
        'Scale=2' 'Idiom="watch"' 'RenditionName="Wrong.png"' \
        'SHA1Digest=("G" * 64)' 'SHA1Digest=("A" * 40)' 'SHA1Digest=("A" * 65)' \
        'SHA1Digest=null' 'Name="Wrong"' 'AssetType="Image"'; do
        expect_rejection phone phone ".[${index}].${mutation}" "rendition ${index}: ${mutation}"
    done
    for field in Opaque PixelWidth PixelHeight Colorspace ColorModel BitsPerComponent Scale Idiom RenditionName SHA1Digest; do
        expect_rejection phone phone "del(.[${index}].${field})" "rendition ${index}: missing ${field}"
    done
done
expect_rejection watch watch '.[0].Opaque = false' 'nonopaque Watch icon'
expect_rejection watch watch '.[0].SHA1Digest = ""' 'empty Watch digest'

echo "Distribution icon policy passed phone, Watch and reordered catalogs; rejected ${rejected} malformed fixtures."
