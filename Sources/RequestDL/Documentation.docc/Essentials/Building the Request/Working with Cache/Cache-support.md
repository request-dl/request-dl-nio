# Caching your responses

Caching requests is crucial for saving costs and unnecessary loading screens. Dive deep into how to use the RequestDL's caching system.

## Overview

TBD.

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
