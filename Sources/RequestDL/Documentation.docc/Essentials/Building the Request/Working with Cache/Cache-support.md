# Caching your responses

Caching requests is crucial for saving costs and unnecessary loading screens. Dive deep into how to use the RequestDL's caching system.

## Overview

Caching requests is crucial for both user experience and reducing unnecessary costs associated with consuming remote APIs.

RequestDL provides two ways to do this: through ``RequestDL/Property/cache(memoryCapacity:diskCapacity:url:)`` or through ``RequestDL/DataCache``.

Depending on the needs of each project, it may be interesting to use both methods, as one of them is completely independent of the request logic.

> Warning: ``RequestDL/DataCache`` does not apply any validation regarding the validity of the cache.

### Property

Configuring and using the cache system directly during the request specification is advantageous because it is a shorter path. Additionally, depending on the ``RequestDL/CacheStrategy`` used, RequestDL checks if the cache is valid at the endpoint, simple as that.

To do this, you need to pay attention to the following points:

1. Specify the ``RequestDL/DataCache/Policy``.
2. Choose the ``RequestDL/CacheStrategy``.
3. Define the storage location with ``RequestDL/Property/cache(memoryCapacity:diskCapacity:url:)``.

Here's an example of how these three points are implemented in practice:

```swift
DataTask {
    BaseURL("apple.com")
        .cachePolicy(.memory)
        .cacheStrategy(.returnCachedDataElseLoad)
        .cache(url: cacheStorageURL)
}
```

Defining the storage location is optional. The default values for memory and disk usage are 2 MB. However, ``RequestDL/DataCache/Policy`` and ``RequestDL/CacheStrategy`` are essential for active caching.

> Important: There are three options to choose where to store the cache: URL, suiteName, or exclusively reserved for the app.

### DataCache

Another way to store the result of a request is by using ``RequestDL/DataCache`` directly. You can even implement your own logic for storing and using RequestDL's default when making the request again.

These are the main usage methods:

@Links(visualStyle: list) {
    - ``RequestDL/DataCache/getCachedData(forKey:policy:)``
    - ``RequestDL/DataCache/setCachedData(_:forKey:)``
    - ``RequestDL/DataCache/remove(forKey:)``
}

> Note: Just like we use methods to specify the storage location in a request specification, the ``RequestDL/DataCache`` initializers are available with the same options.

## Topics

### The caching system

- ``RequestDL/DataCache``
- ``RequestDL/CachedData``
- ``RequestDL/EmptyCachedDataError``

### Defining the strategy

- ``RequestDL/CacheStrategy``
- ``RequestDL/Property/cacheStrategy(_:)``

### Defining the policy

- ``RequestDL/DataCache/Policy``
- ``RequestDL/DataCache/Policy/Set``
- ``RequestDL/Property/cachePolicy(_:)``

### Initializing the cache  

- ``RequestDL/Property/cache(memoryCapacity:diskCapacity:)``
- ``RequestDL/Property/cache(memoryCapacity:diskCapacity:suiteName:)``
- ``RequestDL/Property/cache(memoryCapacity:diskCapacity:url:)``
