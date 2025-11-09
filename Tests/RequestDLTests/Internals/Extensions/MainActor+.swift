//
//  File.swift
//  request-dl
//
//  Created by Brenno de Moura on 06/09/25.
//

import Foundation

extension MainActor {

    @discardableResult
    static func sync<Value: Sendable>(_ block: @MainActor () throws -> Value) rethrows -> Value {
        if Thread.isMainThread {
            return try assumeIsolated(block)
        } else {
            return try DispatchQueue.main.sync(execute: block)
        }
    }
}
