# Adding a secure connection protocol

Explore the different methods to maintain a secure connection with the server and implement the one that best suits your business needs.

## Overview

Having and maintaining a secure connection is extremely critical in any application and is essential for software security and integrity. SwiftNIO and AsyncHTTPClient make the necessary TLS configuration super easy by providing simple certificate handling.

As supported by SwiftNIO, we have the following definitions:

1. **Trust**  
   Validated after receiving the server's certificate to determine whether it is trustworthy.

2. **Client Authorization**  
   A local certificate is sent to the server to establish client trust.

3. **PSK**  
   Authentication using a pre-shared symmetric key between client and server.

4. **SPKI Pinning**  
   Cryptographic pinning of the server's public key structure for explicit trust validation.

> Warning: Any TLS configuration must be performed within ``RequestDL/SecureConnection``. Otherwise, RequestDL will not recognize the declarations.

### SPKI Pinning

SPKI (SubjectPublicKeyInfo) pinning provides defense-in-depth security beyond standard certificate validation. By pinning the cryptographic hash of the server's public key structure, you ensure connections only succeed with certificates containing the exact expected public key — even if a compromised Certificate Authority issues a fraudulent certificate.

#### Key benefits
- ✅ Survives legitimate certificate rotations (same key, new expiration)
- ✅ Prevents algorithm downgrade attacks (algorithm identifier is included in SPKI)
- ✅ Blocks MITM attacks from compromised CAs
- ✅ Stronger security than full-certificate pinning

#### Configuration essentials
- **Active pins**: Hashes of currently deployed production certificates
- **Backup pins**: Pre-deployed hashes for upcoming rotations (*required in production*)
- **Policy modes**:
  - `.strict`: Terminate connections on pin mismatch (production)
  - `.audit`: Allow connections but log warnings (staging/debugging)

#### Example implementation
```swift
SecureConnection {
    SPKIPinning(policy: .strict) {
        SPKIActivePins {
            SPKIHash("base64-active-pin-1")
            SPKIHash("base64-active-pin-2")
        }
        SPKIBackupPins {
            SPKIHash("base64-backup-pin")
        }
    }
}
```

> Warning: Always deploy non-empty backup pins in production. Omitting backup pins risks catastrophic service disruption during certificate rotation. Deploy backup pins ≥30 days before certificate expiration.

> Important: Generate SPKI hashes from the DER-encoded public key structure (not the full certificate):
> ```bash
> openssl s_client -connect example.com:443 -servername example.com 2>/dev/null | \
>   openssl x509 -pubkey -noout | \
>   openssl pkey -pubin -outform der | \
>   openssl dgst -sha256 -binary | \
>   openssl base64 -A
> ```

### Trust

There are two layers of server validation configuration. The first layer is the base certificates to trust the server we are connecting to. The second layer is additional certificates that are also used for the same purpose.

There are two ways to configure the base certificates: one using ``RequestDL/DefaultTrustRoots`` and the other using ``RequestDL/TrustRoots``. The first one uses system certificates, while the second one completely replaces the certificate validation to use only the specified ones.

#### DefaultTrustRoots
```swift
DefaultTrustRoots()
```

#### TrustRoots
```swift
TrustRoots {
  Certificate(file1, format: .pem)
  Certificate(file2, format: .pem)
}
```

After defining the base certificates, you need to specify additional certificates to be used as alternative server validation. It is optional and can be explored depending on the server's specifications.

> Tip: In applications where security is not the highest priority, combine ``RequestDL/DefaultTrustRoots`` with ``RequestDL/AdditionalTrustRoots`` to include both system certificates and custom trust anchors.

### Client Authorization

Authentication of the client is performed by combining public and private certificates using ``RequestDL/Certificates`` and ``RequestDL/PrivateKey``.

#### Certificates
Represents public certificates used by the client to authenticate with the server.
```swift
Certificates {
    Certificate(file1, format: .pem)
    Certificate(file2, format: .pem)
}
```

#### PrivateKey
The private key corresponding to the public certificate.
```swift
PrivateKey(privateFile1)
```
> Important: Password-protected private keys use the `password:` parameter during initialization.

### PSK

Pre-Shared Key (PSK) authentication uses symmetric keys shared between client and server. Configure using ``SSLPSKIdentityResolver``, secured via ``StoredObject`` for efficiency:
```swift 
struct GithubAPI: Property {
    @StoredObject var psk = GithubPSKResolver()

    var body: some Property {
        SecureConnection {
            PSKIdentity(psk)
        }
    }
}
```

> Warning: Exclusively choose either Trust/Client Authorization *or* PSK. Defining both may cause undefined behavior.

### Optimizations

Although ``RequestDL/Property/body-swift.property`` executes per request, RequestDL optimizes certificate loading to avoid redundant file reads.

> Warning: Runtime certificate updates require changing the filename. RequestDL caches certificates by filename and won't detect content changes. Idle periods may trigger cache expiration, causing fallback to original certificates unless filenames change.

## Topics

### Certificate fundamentals
- ``RequestDL/Certificate``

### Server trust configuration
- ``RequestDL/DefaultTrustRoots``
- ``RequestDL/TrustRoots``
- ``RequestDL/AdditionalTrustRoots``
- ``RequestDL/DefaultTrusts``
- ``RequestDL/Trusts``
- ``RequestDL/AdditionalTrusts``

### SPKI Pinning
- ``RequestDL/SPKIPinning``
- ``RequestDL/SPKIActivePins``
- ``RequestDL/SPKIBackupPins``
- ``RequestDL/SPKIHash``

### Client authorization
- ``RequestDL/Certificates``
- ``RequestDL/PrivateKey``

### PSK authentication
- ``RequestDL/PSKIdentity``
- ``RequestDL/SSLPSKIdentityResolver``

### TLS configuration
- ``RequestDL/SecureConnection``
- ``RequestDL/TLSVersion``
- ``RequestDL/TLSCipher``
- ``RequestDL/CertificateVerification``
- ``RequestDL/SignatureAlgorithm``
- ``RequestDL/RenegotiationSupport``
- ``RequestDL/SSLKeyLogger``
