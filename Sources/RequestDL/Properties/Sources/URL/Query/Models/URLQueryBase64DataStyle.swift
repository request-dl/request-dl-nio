//
//  File.swift
//  
//
//  Created by Brenno on 04/05/23.
//

import Foundation

public struct URLQueryBase64DataStyle: URLQueryDataStyle {

    let options: Data.Base64EncodingOptions?

    public func callAsFunction(_ data: Data) -> String {
        if let options {
            return data.base64EncodedString(options: options)
        } else {
            return data.base64EncodedString()
        }
    }
}

extension URLQueryDataStyle where Self == URLQueryBase64DataStyle {

    public static var base64: URLQueryBase64DataStyle {
        .init(options: nil)
    }

    public static func base64(options: Data.Base64EncodingOptions) -> URLQueryBase64DataStyle {
        .init(options: options)
    }
}
