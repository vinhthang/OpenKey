#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/OpenKeySwift.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"

# Helper mode: --setup-cert generates a self-signed code-signing identity in login keychain
if [[ "${1:-}" == "--setup-cert" ]]; then
    CERT_NAME="OpenKey Local Signer"
    echo "=== Generating self-signed code signing certificate: ${CERT_NAME} ==="
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "${TMP_DIR}"' EXIT
    OPENSSL_BIN="/usr/bin/openssl"
    
    cat > "${TMP_DIR}/cert.cnf" << 'EOF'
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3_codesign

[ dn ]
CN = OpenKey Local Signer

[ v3_codesign ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF

    "${OPENSSL_BIN}" req -new -x509 -newkey rsa:2048 -nodes \
        -keyout "${TMP_DIR}/key.pem" \
        -out "${TMP_DIR}/cert.pem" \
        -days 3650 \
        -config "${TMP_DIR}/cert.cnf"
        
    "${OPENSSL_BIN}" pkcs12 -export \
        -inkey "${TMP_DIR}/key.pem" \
        -in "${TMP_DIR}/cert.pem" \
        -out "${TMP_DIR}/cert.p12" \
        -passout pass:openkey
        
    security import "${TMP_DIR}/cert.p12" -k ~/Library/Keychains/login.keychain-db -P openkey -T /usr/bin/codesign
    echo "Certificate '${CERT_NAME}' imported into login keychain."
    open -a "Keychain Access"
    exit 0
fi

echo "=== Building OpenKeySwift release binary ==="
swift build -c release --package-path "${SCRIPT_DIR}"

BUILD_PRODUCTS_DIR="$(swift build -c release --package-path "${SCRIPT_DIR}" --show-bin-path)"
BIN_PATH="${BUILD_PRODUCTS_DIR}/OpenKeySwiftApp"

# Emit dynamic library for script / test runners
swiftc -emit-library "${BUILD_PRODUCTS_DIR}/OpenKeySwiftCore.o" "${BUILD_PRODUCTS_DIR}/OpenKeyEngineBridge.o" -lc++ -o "${BUILD_PRODUCTS_DIR}/libOpenKeySwiftCore.dylib"

echo "=== Assembling OpenKeySwift.app bundle ==="
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/OpenKeySwift"
chmod +x "${MACOS_DIR}/OpenKeySwift"
cp "${SCRIPT_DIR}/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Stamp dynamic build version (REQ-013, ADR-012)
BUILD_VERSION="1.$(date -u +%Y%m%d%H%M%S)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION}" "${APP_BUNDLE}/Contents/Info.plist" || \
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
echo "=== Stamped CFBundleVersion: ${BUILD_VERSION} ==="

# Detect Signing Identity (REQ-009, REQ-012, REQ-013)
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "${SIGNING_IDENTITY}" ]]; then
    KEYCHAIN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -E '^[[:space:]]*[0-9]+\)' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    if [[ -n "${KEYCHAIN_IDENTITY}" ]]; then
        SIGNING_IDENTITY="${KEYCHAIN_IDENTITY}"
        echo "=== Found Keychain signing identity: ${SIGNING_IDENTITY} ==="
    else
        SIGNING_IDENTITY="-"
        echo "=== No certificate found in Keychain; using ad-hoc (-) signing ==="
    fi
else
    echo "=== Using specified signing identity: ${SIGNING_IDENTITY} ==="
fi

echo "=== Signing OpenKeySwift.app with identity '${SIGNING_IDENTITY}' ==="
if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    codesign --force --deep \
        --sign "${SIGNING_IDENTITY}" \
        --identifier com.tuyenmai.openkey.swift \
        -r='designated => identifier "com.tuyenmai.openkey.swift"' \
        --entitlements "${SCRIPT_DIR}/OpenKeySwift.entitlements" \
        "${APP_BUNDLE}"
else
    codesign --force --deep \
        --sign "${SIGNING_IDENTITY}" \
        --identifier com.tuyenmai.openkey.swift \
        --entitlements "${SCRIPT_DIR}/OpenKeySwift.entitlements" \
        "${APP_BUNDLE}"
fi

echo "=== Build completed successfully: ${APP_BUNDLE} ==="

DEPLOY_DIR="/Applications"
if [[ -d "${DEPLOY_DIR}" && -w "${DEPLOY_DIR}" ]]; then
    echo "=== Deploying to ${DEPLOY_DIR}/OpenKeySwift.app ==="
    if pgrep -x "OpenKeySwift" >/dev/null 2>&1; then
        pkill -x "OpenKeySwift"
    fi
    rm -rf "${DEPLOY_DIR}/OpenKeySwift.app"
    cp -R "${APP_BUNDLE}" "${DEPLOY_DIR}/OpenKeySwift.app"
    echo "=== Deployed successfully to ${DEPLOY_DIR}/OpenKeySwift.app ==="
    open -a "${DEPLOY_DIR}/OpenKeySwift.app"
fi
