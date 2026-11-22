#!/bin/bash
# Собирает «StartForMac.app» (universal: arm64 + Intel, macOS 12+).
# Builds «StartForMac.app» (universal: arm64 + Intel, macOS 12+).
#
#   ./build.sh                         — сборка; подписывается, если задан SIGN_ID
#                                        (в .sign.local или в командной строке), иначе ad-hoc
#   SIGN_ID="<хэш или имя сертификата Developer ID Application>" \
#   NOTARY_PROFILE="<профиль notarytool>" ./build.sh
#                                      — подпись Developer ID + нотаризация, на выходе StartForMac.zip
#   NOTARY_PROFILE= ./build.sh         — быстрая сборка с подписью, без нотаризации
set -e
cd "$(dirname "$0")"
# Личные настройки подписи читаются из файла .sign.local (он не попадает в git).
# Значения из командной строки главнее. Пример файла: .sign.local.example
[ -f .sign.local ] && . ./.sign.local
APP="StartForMac.app"
ZIP="StartForMac.zip"
TMP="$(mktemp -d)"
STAGE="$TMP/$APP"

rm -f "$ZIP"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

swiftc -O -target arm64-apple-macos12.0  Sources/*.swift -o "$TMP/arm64"
swiftc -O -target x86_64-apple-macos12.0 Sources/*.swift -o "$TMP/x86_64"
lipo -create "$TMP/arm64" "$TMP/x86_64" -output "$STAGE/Contents/MacOS/StartForMac"

cp Info.plist "$STAGE/Contents/Info.plist"
[ -d Cards ] && cp -R Cards "$STAGE/Contents/Resources/Cards"     # картинки и звуки карт для «Косынки»
[ -d SnakeRes ] && cp -R SnakeRes "$STAGE/Contents/Resources/SnakeRes"   # картинки и звуки для Snake
[ -d ArcanRes ] && cp -R ArcanRes "$STAGE/Contents/Resources/ArcanRes"   # картинки и звуки для Arcan
[ -d DiamRes ] && cp -R DiamRes "$STAGE/Contents/Resources/DiamRes"       # картинки и звуки для Diam
[ -d FinderTemplates ] && cp -R FinderTemplates "$STAGE/Contents/Resources/FinderTemplates"   # пустые документы для «Создать» в Finder
[ -d PacmanRes ] && cp -R PacmanRes "$STAGE/Contents/Resources/PacmanRes"   # картинки и звуки для Pacman

swiftc -O Tools/make_icon.swift -o "$TMP/make_icon"
"$TMP/make_icon" "$TMP"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$STAGE/Contents/Resources/AppIcon.icns"

# Расширение Finder («Создать» в контекстном меню): отдельный модуль внутри приложения, обязательно в песочнице
APPEX="$STAGE/Contents/PlugIns/StartFinderExt.appex"
mkdir -p "$APPEX/Contents/MacOS"
for A in arm64 x86_64; do
  swiftc -O -target "$A-apple-macos12.0" -application-extension -module-name StartFinderExt FinderExt/*.swift \
    -Xlinker -e -Xlinker _NSExtensionMain -o "$TMP/ext_$A"
done
lipo -create "$TMP/ext_arm64" "$TMP/ext_x86_64" -output "$APPEX/Contents/MacOS/StartFinderExt"
cp FinderExt/Info.plist "$APPEX/Contents/Info.plist"
if [ -n "$SIGN_ID" ]; then
  codesign --force --options runtime --timestamp --entitlements FinderExt/FinderExt.entitlements --sign "$SIGN_ID" "$APPEX"
else
  codesign --force --entitlements FinderExt/FinderExt.entitlements --sign - "$APPEX"
fi

if [ -n "$SIGN_ID" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$STAGE"
  codesign --verify --strict --verbose=2 "$STAGE"
  if [ -n "$NOTARY_PROFILE" ]; then
    ditto -c -k --keepParent "$STAGE" "$TMP/notarize.zip"
    xcrun notarytool submit "$TMP/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$STAGE"
    spctl --assess --type execute --verbose "$STAGE"
  fi
else
  codesign --force --sign - "$STAGE"
fi

# Обновляем StartForMac.app НА МЕСТЕ, не удаляя саму папку: так значок в Dock не пропадает при пересборке
mkdir -p "$APP"
rsync -a --delete "$STAGE/" "$APP/"
codesign --verify --strict "$APP"

if [ -n "$SIGN_ID" ]; then
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Готово (подписано Developer ID): $(pwd)/$APP  и  $(pwd)/$ZIP"
else
  echo "Готово (ad-hoc подпись, только для своего Мака): $(pwd)/$APP"
fi
rm -rf "$TMP"
