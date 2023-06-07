//
//  File.swift
//  
//
//  Created by Brenno on 07/06/23.
//

import Foundation
import Logging

extension Modifiers {

    public struct Logger<Input: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let logger: Logging.Logger

        // MARK: - Public methods
        public func body(_ task: Content) async throws -> Input {
            try await task
                .environment(\.logger, logger)
                .result()
        }
    }
}

extension RequestTask {

    public func logger(
        _ logger: Logger
    ) -> ModifiedRequestTask<Modifiers.Logger<Element>> {
        modifier(Modifiers.Logger(logger: logger))
    }
}
