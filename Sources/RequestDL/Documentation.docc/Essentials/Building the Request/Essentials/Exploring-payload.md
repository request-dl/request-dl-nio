# Exploring the payload

The request body supports multiple data types. Learn about all the supported ones.

## Overview

TBD.

### Additional headers

TBD. See for example: ``RequestDL/Form/init(name:filename:contentType:url:headers:)``.

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
