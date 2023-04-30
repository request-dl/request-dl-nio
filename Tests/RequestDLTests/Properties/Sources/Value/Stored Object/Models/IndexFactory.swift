//
//  File.swift
//  
//
//  Created by Brenno on 28/04/23.
//

import Foundation

protocol IndexFactory: AnyObject {

    var rawValue: Int { get }

    init()
}
