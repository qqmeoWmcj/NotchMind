#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$ROOT_DIR/NotchMind"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="NotchMind"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"
STAGING_DIR="$DIST_DIR/dmg-staging"

echo "==> Building ${APP_NAME} (release, arm64)..."
cd "$PKG_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Error: release binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE" "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$PKG_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
chmod +x "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

echo "==> Generating AppIcon.icns..."
TMP_ICON_DIR="$(mktemp -d)"
swift - "$TMP_ICON_DIR/icon_1024.png" <<'SWIFT'
import AppKit
import CoreGraphics

let outPath = CommandLine.arguments[1]
let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let rect = CGRect(x: 64, y: 64, width: 896, height: 896)
let bgPath = CGPath(roundedRect: rect, cornerWidth: 210, cornerHeight: 210, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let cs = CGColorSpaceCreateDeviceRGB()
let bgGrad = CGGradient(
    colorsSpace: cs,
    colors: [CGColor(red: 0.11, green: 0.14, blue: 0.22, alpha: 1), CGColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 64, y: 960), end: CGPoint(x: 960, y: 64), options: [])
let notchPath = CGPath(roundedRect: CGRect(x: 292, y: 780, width: 440, height: 96), cornerWidth: 48, cornerHeight: 48, transform: nil)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
ctx.addPath(notchPath)
ctx.fillPath()
let cx: CGFloat = 512, cy: CGFloat = 450, r: CGFloat = 210, inner: CGFloat = 56
let spark = CGMutablePath()
spark.move(to: CGPoint(x: cx, y: cy + r))
spark.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + inner, y: cy + inner))
spark.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx + inner, y: cy - inner))
spark.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx - inner, y: cy - inner))
spark.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx - inner, y: cy + inner))
spark.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 48, color: CGColor(red: 0.35, green: 0.85, blue: 1, alpha: 0.65))
ctx.addPath(spark)
ctx.clip()
let sparkGrad = CGGradient(
    colorsSpace: cs,
    colors: [CGColor(red: 0.45, green: 0.90, blue: 1, alpha: 1), CGColor(red: 0.56, green: 0.58, blue: 1, alpha: 1)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(sparkGrad, start: CGPoint(x: cx - r, y: cy + r), end: CGPoint(x: cx + r, y: cy - r), options: [])
ctx.restoreGState()
ctx.restoreGState()
ctx.addPath(bgPath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.24))
ctx.setLineWidth(14)
ctx.strokePath()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
SWIFT
ICONSET="$TMP_ICON_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP_ICON_DIR/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  s2=$((s * 2))
  sips -z $s2 $s2 "$TMP_ICON_DIR/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$TMP_ICON_DIR"

echo "==> Ad-hoc codesigning with stable bundle identifier (com.jackma.notchmind)..."
codesign --force --deep --sign - --identifier "com.jackma.notchmind" "$APP_BUNDLE"

echo "==> Packaging ${DMG_PATH}..."
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "==> Done!"
ls -lh "$APP_BUNDLE/Contents/MacOS/${APP_NAME}" "$DMG_PATH"
