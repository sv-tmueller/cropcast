# CropCast app icon

The source is `make-icon.swift`, which draws the icon with CoreGraphics. Nothing external is needed.

Concept: an ultrawide monitor with one 16:9 region marked by CropCast's corner brackets. The region is projected out as its own floating screen with a broadcast mark: crop, then cast.

Regenerate:

    swift make-icon.swift AppIcon-1024.png
    mkdir AppIcon.iconset
    for s in 16 32 128 256 512; do
      sips -z $s $s AppIcon-1024.png --out AppIcon.iconset/icon_${s}x${s}.png
      sips -z $((s*2)) $((s*2)) AppIcon-1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
    done
    iconutil -c icns AppIcon.iconset -o AppIcon.icns && rm -rf AppIcon.iconset
