//
//  FormFile.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
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

/**
 A property type for a file in a form data request.

 `FormFile` can be used to include a file as part of a form data request.

 You can initialize a `FormFile` object with a key, a file URL, and an content type.

 ```swift
 FormFile(
     key: "my_file",
     URL(fileURLWithPath: "/path/to/file"),
     withType: .png
 )
 ```
*/
public struct FormFile: Property {

    public typealias Body = Never

    let url: URL
    let key: String
    let fileName: String
    let contentType: ContentType

    public init(
        _ url: URL,
        forKey key: String,
        fileName: String?, // if nil, will get the file name from URL provided
        type: ContentType? // if nil, will get the contentType from URL or use application/octet-stream if fails
    ) {
        self.url = url
        self.key = key
        self.fileName = fileName ?? {
            let contents = url.lastPathComponent.split(separator: ".")

            guard contents.count > 1 else {
                return contents.joined(separator: ".")
            }

            return contents.dropLast().joined(separator: ".")
        }()
        self.contentType = type ?? {
            guard
                !url.pathExtension.isEmpty,
                let contentType = ContentType.allCases.first(where: {
                    $0.rawValue.contains(url.pathExtension)
                })
            else { return "application/octet-stream" }

            return contentType
        }()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension FormFile: PrimitiveProperty {

    func makeObject() -> FormObject {
        FormObject {
            let data = (try? Data(contentsOf: url)) ?? Data()

            return PartFormRawValue(data, forHeaders: [
                kContentDisposition: kContentDispositionValue(fileName, forKey: key),
                "Content-Type": contentType
            ])
        }
    }
}
