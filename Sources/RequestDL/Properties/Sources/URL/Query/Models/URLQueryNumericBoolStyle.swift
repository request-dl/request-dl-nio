//
//  File.swift
//  
//
//  Created by Brenno on 04/05/23.
//

import Foundation

public struct URLQueryNumericBoolStyle: URLQueryBoolStyle {

    public func callAsFunction(_ flag: Bool) -> String {
        if flag {
            return "1"
        } else {
            return "0"
        }
    }
}

extension URLQueryBoolStyle where Self == URLQueryNumericBoolStyle {

    public static var numeric: URLQueryNumericBoolStyle {
        URLQueryNumericBoolStyle()
    }
}
