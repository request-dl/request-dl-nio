//
//  File.swift
//  
//
//  Created by Brenno on 20/03/23.
//

import Foundation

public enum Response {
    case upload(Int)
    case download(ResponseHead, AsyncBytes)
}
