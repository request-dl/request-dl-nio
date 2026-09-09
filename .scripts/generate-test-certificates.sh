#!/usr/bin/env bash
#
# See LICENSE for this package's licensing information.
#
# Regenerates the self-signed TLS fixtures under Tests/RequestDLTests/Resources/{server,client,client_password}/,
# consumed by the `Certificates()` test helper (Tests/RequestDLTestSupport/Certificates/Certificates.swift).
#
# Run this:
#   - whenever CertificateFixturesExpirationTests fails (a fixture has expired)
#   - roughly once a year otherwise -- the certificates below are intentionally short-lived (see DAYS)
#
# Why regenerate at all, and why short-lived: the original fixtures (see the recipe this replaces in
# Tests/RequestDLTests/Resources/SSL.md) were issued for 30 years with no Extended Key Usage or SAN.
# `SecTrustEvaluateWithError` -- the URLSession executor's certificate validation, unlike the
# NIOSSL/BoringSSL path the rest of this suite exercises -- rejects that outright, even when the
# certificate is explicitly anchored as trusted:
#
#   "certificate is not standards compliant" /
#   "Certificate exceeds maximum temporal validity period, Extended key usage does not match
#   certificate usage"
#
# See URLSESSION_TASK.md, Phase 5e, for the full finding. DAYS below is kept under Apple's enforced
# cap deliberately, which is also why these need periodic regeneration rather than a multi-decade
# certificate -- CertificateFixturesExpirationTests exists specifically to turn a stale fixture into
# an immediate, actionable test failure instead of a confusing TLS handshake error discovered later.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RESOURCES_DIR="Tests/RequestDLTests/Resources"
DAYS=397
CLIENT_PASSWORD="password123"

generate() {
    local dir="$1" stem="$2" extended_key_usage="$3" subject_alt_name="$4" passphrase="$5"

    local out_dir="$RESOURCES_DIR/$dir"
    mkdir -p "$out_dir"

    local private_pem="$out_dir/$stem.private.pem"
    local public_pem="$out_dir/$stem.public.pem"
    local private_cer="$out_dir/$stem.private.cer"
    local public_cer="$out_dir/$stem.public.cer"

    local key_args=()
    local pass_in_args=()
    if [[ -n "$passphrase" ]]; then
        # `-aes256` is required alongside `-passout` -- `genrsa -passout` with no cipher flag is
        # silently ignored by modern openssl and produces an unencrypted key.
        key_args+=(-aes256 -passout "pass:$passphrase")
        pass_in_args+=(-passin "pass:$passphrase")
    fi

    openssl genrsa ${key_args[@]+"${key_args[@]}"} -out "$private_pem" 2048

    # No `keyUsage` extension here, deliberately -- these self-signed certificates double as their
    # own trust anchor in most tests (`TrustRoots(server.certificateURL)`, direct, no real CA
    # chain), and BoringSSL (NIOSSL's backend) enforces a critical `keyUsage` strictly: a leaf-only
    # usage set (no `keyCertSign`) makes it refuse to treat the certificate as a valid anchor at
    # all, breaking every NIOSSL-backed test that relies on it, not just the URLSession ones this
    # script exists for. `extendedKeyUsage` is a separate extension with no such CA-eligibility
    # side effect, which is why only it is set here -- matches what SecTrustEvaluateWithError
    # actually complained about (see the file header).
    local ext_args=(
        -addext "extendedKeyUsage=$extended_key_usage"
    )
    if [[ -n "$subject_alt_name" ]]; then
        ext_args+=(-addext "subjectAltName=$subject_alt_name")
    fi

    openssl req -x509 -new -sha256 -days "$DAYS" \
        -key "$private_pem" ${pass_in_args[@]+"${pass_in_args[@]}"} \
        -subj "/CN=localhost" \
        "${ext_args[@]}" \
        -out "$public_pem"

    openssl x509 -inform PEM -outform DER -in "$public_pem" -out "$public_cer"
    openssl rsa -inform PEM -outform DER -in "$private_pem" ${pass_in_args[@]+"${pass_in_args[@]}"} -out "$private_cer"

    echo "Generated $out_dir/$stem.{public,private}.{pem,cer} -- expires in $DAYS days"
}

# Server: needs serverAuth EKU + a SAN covering LocalServer's "localhost" host -- what
# SecTrustEvaluateWithError actually checks the leaf certificate against.
generate "server" "server" "serverAuth" "DNS:localhost,IP:127.0.0.1" ""

# Client: needs clientAuth EKU. No SAN requirement -- client certificates aren't validated against
# a hostname.
generate "client" "client" "clientAuth" "" ""

# Same as "client", but with an encrypted private key -- exercises the password-protected
# PrivateKey(_:format:password:) path. The passphrase is hardcoded across several tests
# (e.g. InternalsPrivateKeyTests) -- keep it in sync if it ever changes here.
generate "client_password" "client.password" "clientAuth" "" "$CLIENT_PASSWORD"

echo "Done. Review the diff under $RESOURCES_DIR and commit it."
