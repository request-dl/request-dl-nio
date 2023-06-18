# Using progress for upload and download requests

Explore how to monitor your requests and track the progress of each operation precisely.

## Overview

The way SwiftNIO and AsyncHTTPClient send and receive data from the server allows for implementing a range of interesting features to handle the raw bytes involved in the operation.

Whether sending a ``RequestDL/Payload`` or a ``RequestDL/Form``, it is possible to serialize the transmission into parts and monitor the upload progress. The same applies to download, as the same process happens internally.

## Monitors

Exploring this feature in RequestDL involves separating the concepts of upload and download, which are represented through the ``RequestDL/AsyncResponse`` object. The foundation of RequestDL is asynchronous and is fully supported by the principles discussed here.

By using the ``RequestDL/Modifiers/Progress`` modifier, we process the sent and received bytes and notify the respective monitor at each stage. For this purpose, the ``RequestDL/UploadProgress`` and ``RequestDL/DownloadProgress`` have been implemented.

## Topics

### Related Documentation

- <doc:Exploring-payload>

### The essentials tasks

- ``RequestDL/UploadTask``
- ``RequestDL/DownloadTask``

### Meet the progress

- ``RequestDL/UploadProgress``
- ``RequestDL/DownloadProgress``
- ``RequestDL/Progress``

### Discover the modifiers

- ``RequestDL/Modifiers/Progress``
- ``RequestDL/Modifiers/IgnoresProgress``
- ``RequestDL/Modifiers/CollectBytes``
- ``RequestDL/Modifiers/CollectData``
