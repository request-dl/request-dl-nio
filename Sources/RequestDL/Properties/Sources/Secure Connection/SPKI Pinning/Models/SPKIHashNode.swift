/*
 See LICENSE for this package's licensing information.
*/

struct SPKIHashNode: PropertyNode {

    let hash: Internals.SPKIHash

    func make(_ make: inout Make) async throws {}
}
