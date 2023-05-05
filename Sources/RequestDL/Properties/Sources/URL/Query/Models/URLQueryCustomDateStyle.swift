//
//  File.swift
//  
//
//  Created by Brenno on 04/05/23.
//

import Foundation

public struct URLQueryCustomDateStyle: URLQueryDateStyle {

    let format: String
    let locale: Locale?
    let timeZone: TimeZone?
    let calendar: Calendar?

    public func callAsFunction(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format

        if let locale {
            formatter.locale = locale
        }

        if let timeZone {
            formatter.timeZone = timeZone
        }

        if let calendar {
            formatter.calendar = calendar
        }

        return formatter.string(from: date)
    }
}

extension URLQueryDateStyle where Self == URLQueryCustomDateStyle {

    public static func custom(
        _ format: String,
        locale: Locale? = nil
    ) -> URLQueryCustomDateStyle {
        URLQueryCustomDateStyle(
            format: format,
            locale: locale,
            timeZone: nil,
            calendar: nil
        )
    }

    public static func custom(
        _ format: String,
        locale: Locale? = nil,
        timeZone: TimeZone,
        calendar: Calendar
    ) -> URLQueryCustomDateStyle {
        URLQueryCustomDateStyle(
            format: format,
            locale: locale,
            timeZone: timeZone,
            calendar: calendar
        )
    }
}
