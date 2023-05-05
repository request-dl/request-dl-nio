//
//  File.swift
//  
//
//  Created by Brenno on 04/05/23.
//

import Foundation

public struct URLQueryLiteralBoolStyle: URLQueryBoolStyle {

    public func callAsFunction(_ flag: Bool) -> String {
        if flag {
            return "true"
        } else {
            return "false"
        }
    }
}

extension URLQueryBoolStyle where Self == URLQueryLiteralBoolStyle {

    public static var literal: URLQueryLiteralBoolStyle {
        URLQueryLiteralBoolStyle()
    }
}
