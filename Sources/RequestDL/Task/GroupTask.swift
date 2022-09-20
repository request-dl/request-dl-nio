import Foundation

public struct GroupTask<Data: Collection, Content: Task>: Task {

    private let data: Data
    private let map: (Data.Element) -> Content

    public init(_ data: Data, content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.map = content
    }
}

extension GroupTask {

    public func response() async throws -> [GroupResult<Data.Element, Content.Element>] {
        try await withThrowingTaskGroup(of: GroupResult<Data.Element, Content.Element>.self) { group in
            for element in data {
                group.addTask {
                    let data = try await map(element).response()
                    return .init(id: element, result: data)
                }
            }

            var stack = [GroupResult<Data.Element, Content.Element>]()

            for try await element in group {
                stack.append(element)
            }

            return stack
        }
    }
}

public struct GroupResult<ID, Element> {

    public let id: ID
    public let result: Element

    init(id: ID, result: Element) {
        self.id = id
        self.result = result
    }
}
