#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

BIN_PATH="$(swift build -c release --package-path "${SCRIPT_DIR}" --show-bin-path)/OpenKeySwiftApp"

echo "=== Assembling OpenKeySwift.app bundle ==="
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/OpenKeySwift"
chmod +x "${MACOS_DIR}/OpenKeySwift"
cp "${SCRIPT_DIR}/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Detect Signing Identity (REQ-009)
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "${SIGNING_IDENTITY}" ]]; then
    # Look for any valid code signing identity in Keychain
    KEYCHAIN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -E '^[[:space:]]*[0-9]+\)' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    if [[ -n "${KEYCHAIN_IDENTITY}" ]]; then
        SIGNING_IDENTITY="${KEYCHAIN_IDENTITY}"
        echo "=== Found Keychain signing identity: ${SIGNING_IDENTITY} ==="
    else
        SIGNING_IDENTITY="-"
        echo "=== No certificate found in Keychain; using ad-hoc (-) signing ==="
    fi
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
