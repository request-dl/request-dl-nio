/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type that enables dynamic member lookup of String values.

 AbstractKeyPath is a struct that conforms to the @dynamicMemberLookup, allowing
 dynamic member lookup of String values. It can be used as a base type for defining
 custom dynamic key paths in Swift.
 */
@dynamicMemberLookup
public struct AbstractKeyPath {

    /**
     A subscript that allows accessing a member of a AbstractKeyPath instance dynamically.

     - Parameter member: The name of the member to access.
     - Returns: The name of the member as a String.
     */
    public subscript(dynamicMember member: String) -> String {
        member
    }
}
