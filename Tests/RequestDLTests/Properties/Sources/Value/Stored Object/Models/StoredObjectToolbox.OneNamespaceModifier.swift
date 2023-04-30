//
//  File.swift
//  
//
//  Created by Brenno on 28/04/23.
//

import Foundation
import RequestDL

extension StoredObjectToolbox {

    struct OneNamespaceModifier: PropertyModifier {

        @Namespace var one

        func body(content: Content) -> some Property {
            content
        }
    }
}
