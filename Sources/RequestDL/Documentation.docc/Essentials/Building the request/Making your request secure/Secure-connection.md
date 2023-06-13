# Adding a secure connection protocol

Explore the different methods to maintain a secure connection with the server and implement the one that best suits your business needs.

## Overview

TBD.

## SecureConnection

TBD. See: ``RequestDL/SecureConnection``.

### Certificate

TBD. See: ``RequestDL/Certificate``.

## Server trust

TBD.

### DefaultTrusts

TBD. See: ``RequestDL/DefaultTrusts``.

### Trusts

TBD. See: ``RequestDL/Trusts``.

### AdditionalTrusts

TBD. See: ``RequestDL/AdditionalTrusts``.

## Client Authentication

TBD.

### Certificates

TBD. See: ``RequestDL/Certificates``.

### PrivateKey

TBD. See: ``RequestDL/PrivateKey``.

### PSKIdentity

TBD. See: ``RequestDL/PSKIdentity``.

## Optimizations

Despite the fact that ``RequestDL/Property/body-swift.property`` is called constantly for each request made, RequestDL contains some optimizations to avoid the need to reload the file.

- Warning: If the certificates are updated at runtime, RequestDL will not automatically switch to the new version. Therefore, when updating the certificate, change the file name to one that has not been used before.

This rule is necessary to avoid the instantiation of new clients provided by `AsyncHTTPClient`. Additionally, if your application remains idle for a certain period of time, RequestDL expires the saved information and then starts using the new certificate, unless measures are taken. 
