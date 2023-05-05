//
//  File.swift
//  
//
//  Created by Brenno on 04/05/23.
//

import Foundation

public protocol URLQueryDataStyle {

    func callAsFunction(_ data: Data) -> String
}
