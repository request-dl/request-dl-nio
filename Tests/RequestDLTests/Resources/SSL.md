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
