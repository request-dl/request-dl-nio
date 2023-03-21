//
//  File.swift
//  
//
//  Created by Brenno on 20/03/23.
//

import Foundation

struct RawTask<Content: Property>: Task {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    func result() async throws -> AsyncResponse {
        let (session, request) = try await Resolver(content).make()
        return try .init(session.request(request).response)
    }
}
