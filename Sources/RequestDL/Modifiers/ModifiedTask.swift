import Foundation

public struct ModifiedTask<Modifier: TaskModifier>: Task {

    public typealias Element = Modifier.Element

    let task: Modifier.Body
    let modifier: Modifier

    init(_ task: Modifier.Body, _ modifier: Modifier) {
        self.task = task
        self.modifier = modifier
    }
}

extension ModifiedTask {

    public func response() async throws -> Modifier.Element {
        try await modifier.task(task)
    }
}
