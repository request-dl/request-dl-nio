//
//  File.swift
//  
//
//  Created by Brenno on 04/05/23.
//

import Foundation

public struct URLQueryISO8601DateStyle: URLQueryDateStyle {

    let timeZone: TimeZone?

    public func callAsFunction(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()

        if let timeZone {
            formatter.timeZone = timeZone
        }

        return formatter.string(from: date)
    }
}

extension URLQueryDateStyle where Self == URLQueryISO8601DateStyle {

    public static var iso8601: URLQueryISO8601DateStyle {
        .init(timeZone: nil)
    }

    public static func iso8601(
        timeZone: TimeZone?
    ) -> URLQueryISO8601DateStyle {
        .init(timeZone: timeZone)
    }
}
