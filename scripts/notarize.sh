#!/bin/zsh
# 正式发布：Developer ID 签名 → 提交 Apple 公证 → 把公证结果钉进 App → 打成 dist/XiaokeBar.zip
# 需要：钥匙串里的 Developer ID Application 证书；notarytool 凭证（先运行一次
#   xcrun notarytool store-credentials xiaoke-notary --key <AuthKey.p8> --key-id <ID> --issuer <Issuer>）
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGN_ID:=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
: "${NOTARY_PROFILE:=xiaoke-notary}"
[[ -n "$SIGN_ID" ]] || { echo "钥匙串里没有 Developer ID Application 证书"; exit 1; }
SIGN_ID="$SIGN_ID" ./scripts/build-app.sh
APP="dist/小克额度栏.app"
ZIP="dist/XiaokeBar.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=2 "$APP"
echo "已签名并公证：$ZIP"
