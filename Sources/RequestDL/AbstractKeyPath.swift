import Foundation

@dynamicMemberLookup
public struct AbstractKeyPath {

    init() {}

    public subscript(dynamicMember member: String) -> String {
        member
    }
}
