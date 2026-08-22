> **Superseded by [`.scripts/generate-test-certificates.sh`](../../../.scripts/generate-test-certificates.sh).**
> The recipe below produces certificates with no Extended Key Usage/SAN and a 30-year validity,
> which `SecTrustEvaluateWithError` (the URLSession executor's TLS validation, see
> `URLSESSION_TASK.md` Phase 5e) rejects outright. Kept here as a historical record of how the
> fixtures used to be generated; run the script instead.

# Generate Certificate with Password

```
openssl genrsa -out private.pem -passout pass:password 2048
```

```
openssl req -new -sha256 -key private.pem -out request.crs -passin pass:password -subj "/CN=localhost"

openssl req -x509 -sha256 -days 10950  -key private.pem -passin pass:password -in request.crs -out public.pem
```

```
openssl x509 -inform PEM -outform DER -in public.pem -out public.cer
openssl x509 -noout -fingerprint -sha1 -inform dec -in public.cer
```

```
openssl rsa -inform PEM -outform DER -in private.pem -passin pass:password -out private.cer
```

# Generate Certificate without Password

```
openssl genrsa -out private.pem 2048
```

```
openssl req -new -sha256 -key private.pem -out request.crs -subj "/CN=localhost"

openssl req -x509 -sha256 -days 10950  -key private.pem -in request.crs -out public.pem
```

```
openssl x509 -inform PEM -outform DER -in public.pem -out public.cer
openssl x509 -noout -fingerprint -sha1 -inform dec -in public.cer
```

```
openssl rsa -inform PEM -outform DER -in private.pem -out private.cer
```
