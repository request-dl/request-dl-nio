//
//  FormFile.swift
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

public struct FormFile: Request {

    public typealias Body = Never

    let url: URL
    let key: String?
    let fileManager: FileManager
    let contentType: ContentType

    public init(
        key: String = "",
        _ url: URL,
        withType contentType: ContentType,
        _ fileManager: FileManager = .default
    ) {
        self.key = key.isEmpty ? nil : key
        self.url = url
        self.fileManager = fileManager
        self.contentType = contentType
    }

    public init(
        key: String = "",
        _ url: URL,
        _ fileManager: FileManager = .default
    ) {
        self.key = key.isEmpty ? nil : key
        self.url = url
        self.fileManager = fileManager

        guard let fileExtension = url.absoluteString.split(separator: ".").last else {
            self.contentType = .custom("any")
            return
        }

        self.contentType = .allCases.first(where: {
            $0.rawValue.contains(fileExtension)
        }) ?? .custom("\(fileExtension)")
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension FormFile: PrimitiveRequest {

    func makeObject() -> FormObject {
        .init(.file(self))
    }
}
