# Adding a secure connection protocol

Explore the different methods to maintain a secure connection with the server and implement the one that best suits your business needs.

## Overview

Having and maintaining a secure connection is extremely critical in any application and is essential for software security and integrity. SwiftNIO and AsyncHTTPClient make the necessary TLS configuration super easy by providing simple certificate handling.

As supported by SwiftNIO, we have the following definitions:

1. Trust

   It is validated after receiving the server's certificate to determine whether it is trustworthy or not to maintain the connection and proceed with the ongoing request.

2. Client Authorization

   A local certificate is sent to the server to establish client trust and retrieve the resulting data from the API process.

3. PSK

   An alternative form of authentication where the client and server share a symmetric key to proceed with the current request.

> Warning: Any configuration involving TLS should be performed within the ``RequestDL/SecureConnection``. Otherwise, RequestDL will not be able to recognize the declared code.

### Trust

There are two layers of server validation configuration. The first layer is the base certificates to trust the server we are connecting to. The second layer is additional certificates that are also used for the same purpose.

There are two ways to configure the base certificates: one using ``RequestDL/DefaultTrusts`` and the other using ``RequestDL/Trusts``. The first one uses system certificates, while the second one completely replaces the certificate validation to use only the specified ones.

#### DefaultTrusts

```swift
DefaultTrusts()
```

#### Trusts

```swift
Trusts {
  Certificate(file1, format: .pem)
  Certificate(file2, format: .pem)
}
```

After defining the base certificates, you need to specify additional certificates to be used as alternative server validation. It is optional and can be explored depending on the server's specifications.

> Tip: In an application where security is not a priority, you can combine ``RequestDL/DefaultTrusts`` with ``RequestDL/AdditionalTrusts`` to include both system certificates and the ones you want to trust.

### Client Authorization

Authentication of the client is performed by combining two certificates, the public and the private. The implementation is done using ``RequestDL/Certificates`` and ``RequestDL/PrivateKey``.

#### Certificates

Represents the public certificates used by the client to authenticate with the server.

```swift
Certificates {
    Certificate(file1, format: .pem)
    Certificate(file2, format: .pem)
}
```

#### PrivateKey

The private certificate is typically used to generate the public certificate.

```swift
PrivateKey(privateFile1)
```

> Important: Private certificates protected by a password can be used by adding the **`password:`** parameter during initialization.

### PSK

Using shared symmetric keys between the server and the client, PSK is a secure way to communicate with the server.

The configuration is simple and only requires implementing the ``SSLPSKIdentityResolver``. When using it in the ``Property``, you should secure the instance of the implemented resolver using ``StoredObject`` to optimize the code.

```swift 
struct GithubAPI: Property {

    @StoredObject var psk = GithubPSKResolver()

    var body: some Property {
        // Other property specifications
        SecureConnection {
            PSKIdentity(psk)
        }
    }
}
```

> Warning: You should exclusively choose either Trust/Client Authorization or PSK. Defining both in the same request can result in unexpected behavior.

### Optimizations

Despite the fact that ``RequestDL/Property/body-swift.property`` is called constantly for each request made, RequestDL contains some optimizations to avoid the need to reload the file.

> Warning: If the certificates are updated at runtime, RequestDL will not automatically switch to the new version. Therefore, when updating the certificate, change the file name to one that has not been used before.

This rule is necessary to avoid the instantiation of new clients provided by `AsyncHTTPClient`. Additionally, if your application remains idle for a certain period of time, RequestDL expires the saved information and then starts using the new certificate, unless measures are taken. 

## Topics

### The basics about certificates

- ``RequestDL/Certificate``

### Configuring the server trust

- ``RequestDL/DefaultTrusts``
- ``RequestDL/Trusts``
- ``RequestDL/AdditionalTrusts``

### Setting up the client authorization

- ``RequestDL/Certificates``
- ``RequestDL/PrivateKey``

### Working with PSK

- ``RequestDL/PSKIdentity``
- ``RequestDL/SSLPSKIdentityResolver``

### The TLS configuration

- ``RequestDL/SecureConnection``
- ``RequestDL/TLSVersion``
- ``RequestDL/TLSCipher``
- ``RequestDL/CertificateVerification``
- ``RequestDL/SignatureAlgorithm``
- ``RequestDL/RenegotiationSupport``
- ``RequestDL/SSLKeyLogger``
