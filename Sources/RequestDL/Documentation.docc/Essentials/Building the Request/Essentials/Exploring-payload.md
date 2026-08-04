# Exploring the payload

The request body supports multiple data types. Learn about all the supported ones.

## Overview

The possibilities of sending a sequence of bytes in a request are endless. Furthermore, for the server to interpret the received bytes, it uses the value of the `Content-Type` header as it is known.

The most common approach is to send a raw sequence of bytes related to a known data type. `application/json` is a frequently used example in mobile applications.

However, a second type of data that appears in some applications is `multipart/form-data`, which has a more complex implementation due to its unique pattern of the data to be sent.

That's why RequestDL provides ``RequestDL/Payload`` and ``RequestDL/Form`` to maximize your calls.

> Tip: Each object has 5 initializers that standardize data configuration in a request: Data, String, URL, Codable, and JSON (also known as [String: Any]).

### Payload

We can consider ``RequestDL/Payload`` as the primitive type for the bytes to be sent in a request. Keep in mind the following 3 central properties of every payload:

1. Data

    Options include `Data`, `String`, `URL`, `Codable`, and `JSON`.

2. Content-Type

    It can be customized by specifying a value of type ``RequestDL/ContentType``. Here is a list of default values:

    - Data: `application/octet-stream`
    - String: `text/plain`
    - URL: Not applicable
    - Codable: `application/json`
    - JSON: `application/json`

3. Content-Length

    Automatically configured based on the length of the byte sequence to be sent as the body.

### Form

Using the `multipart/form-data` data format for ``RequestDL/Form``, there are several implementations to simplify the process of constructing the request body.

> Important: Declaring an independent ``RequestDL/Form`` makes it behave as the sole object for the body. If you want to specify multiple `form-data`, you **should** group them into a ``RequestDL/FormGroup``.

``RequestDL/Form`` follows the same initialization principles as ``RequestDL/Payload`` with one difference, which is the need to specify the `name` parameter and optionally, the `filename`. This requirement is part of the `form-data` standard definition.

Additionally, a powerful feature that can be explored according to the needs of each project and service is the ability to specify additional headers for a single `form-data` using the `headers:` parameter during the initialization of ``RequestDL/Form``.

### URL Encoded

Both objects support ``RequestDL/URLEncoder``, which operates on the body by applying a specific ``RequestDL/Charset`` and using ``RequestDL/ContentType/formURLEncoded``.

> Note: The ``RequestDL/Payload`` object has an internal check. If the content type is `application/x-www-form-urlencoded` and the endpoint method is ``RequestDL/HTTPMethod/get`` or ``RequestDL/HTTPMethod/head``, the body is converted into URL parameters when it is in `Codable` or `JSON` format.

Fine-grained control of object encoding using ``RequestDL/ContentType/formURLEncoded`` is done as follows:

```swift
Payload(userModel, contentType: .formURLEncoded)
    .charset(.utf8)
    .urlEncoder(.init())

// Result: name=John&age=20
```

## Topics

### Inserting bytes in the request body

- ``RequestDL/Payload``
- ``RequestDL/EncodingPayloadError``

### Using the multipart form data

- ``RequestDL/Form``
- ``RequestDL/FormGroup``

### Setting content type

- ``RequestDL/ContentType``

### Making the body URL encoded

- ``RequestDL/URLEncoder``
- ``RequestDL/QueryItem``
- ``RequestDL/URLEncoderError``
- ``RequestDL/Property/urlEncoder(_:)``

### Specifying the content charset

- ``RequestDL/Charset``
- ``RequestDL/Property/charset(_:)``

### Configure how the data will be uploaded

- ``RequestDL/Property/payloadChunkSize(_:)``
- ``RequestDL/Property/payloadPartLength(_:)``

### Setting up the download strategy

- ``RequestDL/ReadingMode``
