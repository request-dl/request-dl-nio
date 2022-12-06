//
//  Modifiers.Decode.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

extension Modifiers {

    public struct Decode<Content: Task, Element: Decodable>: TaskModifier where Content.Element == TaskResult<Data> {

        let type: Element.Type
        let decoder: JSONDecoder
        private let contentType: DecodeContentType

        fileprivate init(_ type: Element.Type, decoder: JSONDecoder, contentType: DecodeContentType) {
            self.type = type
            self.decoder = decoder
            self.contentType = contentType
        }

        public func task(_ task: Content) async throws -> TaskResult<Element> {
            let result = try await task.response()

            return .init(
                response: result.response,
                data: try decoder.decode(type, from: flatMap(result.data))
            )
        }
    }
}

extension Modifiers.Decode {

    private func flatMap(_ data: Data) -> Data {
        switch contentType {
        case .plain:
            return data
        case .array:
            return data.isEmpty ? "[]".data(using: .utf8) ?? data : data
        case .dictionary:
            return data.isEmpty ? "{}".data(using: .utf8) ?? data : data
        }
    }
}

extension Task where Element == TaskResult<Data> {

    public func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedTask<Modifiers.Decode<Self, T>> {
        modify(Modifiers.Decode(type, decoder: decoder, contentType: .plain))
    }

    public func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedTask<Modifiers.Decode<Self, T>> where T: Collection {
        modify(Modifiers.Decode(type, decoder: decoder, contentType: .array))
    }

    public func decode<Key: Decodable, Value: Decodable>(
        _ type: [Key: Value].Type,
        decoder: JSONDecoder = .init()
    ) -> ModifiedTask<Modifiers.Decode<Self, [Key: Value]>> {
        modify(Modifiers.Decode(type, decoder: decoder, contentType: .dictionary))
    }
}

private enum DecodeContentType {
    case plain
    case array
    case dictionary
}
