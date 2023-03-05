//
//  FormType.swift
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

enum FormType {
    case data(FormData)
    case file(FormFile)
    case value(FormValue)

    var data: Data {
        switch self {
        case .data(let formData):
            return reduce(formData)
        case .file(let formFile):
            return reduce(formFile)
        case .value(let formValue):
            return reduce(formValue)
        }
    }

    func reduce(_ formData: FormData) -> Data {
        var data = Data()

        data.append(FormUtils.disposition(formData.key, formData.fileName, withType: formData.contentType))
        data.append(Foundation.Data("\(FormUtils.breakLine)".utf8))
        data.append(formData.data)

        return data
    }

    func reduce(_ formFile: FormFile) -> Data {
        guard
            let fileData = try? Data(contentsOf: formFile.url),
            let fileName = formFile.url.absoluteString.split(separator: "/").last
        else {
            fatalError(
                "\(formFile.url.absoluteString) is not a file or it doesn't contains a valid file name"
            )
        }

        var data = Data()

        data.append(FormUtils.disposition(formFile.key, fileName, withType: formFile.contentType))
        data.append(Foundation.Data("\(FormUtils.breakLine)".utf8))
        data.append(fileData)

        return data
    }

    func reduce(_ formValue: FormValue) -> Data {
        var data = Data()

        data.append(FormUtils.disposition(formValue.key))
        data.append(Foundation.Data("\(FormUtils.breakLine)".utf8))
        if let formData = formValue.value as? Data {
            data.append(formData)
        } else {
            data.append(Foundation.Data("\(formValue.value)".utf8))
        }

        return data
    }
}
