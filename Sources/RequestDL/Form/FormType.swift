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
            let fileData = formFile.fileManager.contents(atPath: formFile.path.absoluteString),
            let fileName = formFile.path.absoluteString.split(separator: "/").last
        else {
            fatalError(
                "\(formFile.path.absoluteString) is not a file or it doesn't contains a valid file name"
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
