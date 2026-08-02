//
//  File.swift
//  request-dl
//
//  Created by Brenno de Moura on 06/09/25.
//

import Foundation

@discardableResult
func performOnMainThread<Value: Sendable>(_ block: @MainActor () throws -> Value) rethrows -> Value {
    if Thread.isMainThread {
        return try MainActor.assumeIsolated(block)
    } else {
        return try DispatchQueue.main.sync(execute: block)
    }
}
