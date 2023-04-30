//
//  File.swift
//  
//
//  Created by Brenno on 28/04/23.
//

import Foundation
import RequestDL

extension StoredObjectToolbox {

    struct Query: Property {

        @StoredObject var factory = Factory()

        var body: some Property {
            RequestDL.Query(factory.rawValue, forKey: "index")
        }
    }
}
