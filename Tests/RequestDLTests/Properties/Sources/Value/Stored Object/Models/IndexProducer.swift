//
//  File.swift
//  
//
//  Created by Brenno on 28/04/23.
//

import Foundation

class IndexProducer {

    private(set) var index = 0

    func callAsFunction() -> Int {
        let index = index
        self.index += 1
        return index
    }
}
