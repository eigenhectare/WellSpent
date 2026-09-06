# Validate the approved production catalog declarations, not an arbitrary
# number of renditions. The MultiSized Image AppIcon container is not a pixel
# rendition; assetutil --validate-file checks the complete catalog separately.
def appearance_key:
  if has("Appearance") | not then "default"
  elif .Appearance == "UIAppearanceDark" then "dark"
  else error("Unexpected AppIcon appearance") end;

($component | if . == "phone" then ["default", "dark"]
              elif . == "watch" then ["default"]
              else error("Unsupported AppIcon component") end) as $expected
| if type != "array" then error("Asset inventory must be an array") else . end
| if all(.[]; type == "object") then . else error("Malformed asset inventory entry") end
| [.[] | select(.Name == "AppIcon" and .AssetType == "Icon Image")]
| map(. as $icon | appearance_key as $appearance
    | if .Opaque == true
        and .PixelWidth == 1024 and .PixelHeight == 1024
        and .Colorspace == "srgb" and .ColorModel == "RGB"
        and .BitsPerComponent == 8 and .Scale == 1
        and .Idiom == $component
        and .RenditionName == (if $appearance == "default" then "AppIcon.png" else "AppIcon-Dark.png" end)
        and (.SHA1Digest | type == "string" and test("^[A-Fa-f0-9]{64}$"))
      then {
        appearance: $appearance,
        renditionName: $icon.RenditionName,
        digest: $icon.SHA1Digest,
        idiom: $icon.Idiom,
        pixelWidth: $icon.PixelWidth,
        pixelHeight: $icon.PixelHeight,
        opaque: $icon.Opaque,
        colorModel: $icon.ColorModel,
        colorspace: $icon.Colorspace,
        bitsPerComponent: $icon.BitsPerComponent,
        scale: $icon.Scale
      }
      else error("Invalid AppIcon rendition metadata") end)
| . as $renditions
| if (map(.appearance) | sort) == ($expected | sort) then
    # Declaration order makes the default digest stable even when assetutil
    # returns dark before default. Exact array equality rejects duplicates.
    [$expected[] as $appearance | $renditions[] | select(.appearance == $appearance)]
  else error("Missing, duplicate or unexpected AppIcon rendition") end
| {
    compiledIconChecked: true,
    compiledIconRenditionDigest: .[0].digest,
    compiledIconRenditions: .
  }
