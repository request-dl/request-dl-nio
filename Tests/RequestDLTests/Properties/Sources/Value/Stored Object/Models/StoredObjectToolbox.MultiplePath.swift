//
//  File.swift
//  
//
//  Created by Brenno on 28/04/23.
//

import Foundation
import RequestDL

extension StoredObjectToolbox {

    struct MultiplePath: Property {

        @StoredObject var factory1 = Factory()
        @StoredObject var factory2 = Factory()

        var body: some Property {
            RequestDL.Path("\(factory1.rawValue)")
            RequestDL.Path("\(factory2.rawValue)")
        }
    }
}
