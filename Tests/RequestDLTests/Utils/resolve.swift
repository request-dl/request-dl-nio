//
//  Resolver+Test.swift
//  
//
//  Created by Brenno Giovanini de Moura on 06/12/22.
//

import Foundation
@testable import RequestDL

func resolve<Content: Request>(
    _ content: Content,
    in delegate: DelegateProxy = .init()
) async -> (URLSession, URLRequest) {
    await Resolver(content).make(delegate)
}
