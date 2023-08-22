/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 This enumeration is used to group different types of modifiers in a single namespace.

 ## Topics

 ### Validating the status code

 - ``RequestDL/Modifiers/AcceptOnlyStatusCode``
 - ``RequestDL/InvalidStatusCodeError``

 ### Performing action at specific status code

 - ``RequestDL/Modifiers/OnStatusCode``

 ### Handling the response

 - ``RequestDL/Modifiers/Decode``
 - ``RequestDL/Modifiers/ExtractPayload``
 - ``RequestDL/Modifiers/KeyPath``

 ### Retrieving a specific value with key

 - ``RequestDL/AbstractKeyPath``
 - ``RequestDL/KeyPathNotFound``
 - ``RequestDL/KeyPathInvalidDataError``

 ### Mapping the result

 - ``RequestDL/Modifiers/Map``
 - ``RequestDL/Modifiers/MapError``
 - ``RequestDL/Modifiers/FlatMap``
 - ``RequestDL/Modifiers/FlatMapError``

 ### Adding logger

 - ``RequestDL/Modifiers/Logger``

 ### The task environment **(Alpha)**

 - ``RequestDL/TaskEnvironmentKey``
 - ``RequestDL/TaskEnvironmentValues``
 - ``RequestDL/Modifiers/Environment``

 ### Erasing the task type

 - ``RequestDL/AnyTask``
 */
public enum Modifiers {}
