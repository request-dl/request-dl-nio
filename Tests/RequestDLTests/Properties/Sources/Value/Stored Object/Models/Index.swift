//
//  File.swift
//  
//
//  Created by Brenno on 28/04/23.
//

import Foundation

class Index {

    let rawValue: Int

    init(_ producer: IndexProducer) {
        rawValue = producer()
    }
}
