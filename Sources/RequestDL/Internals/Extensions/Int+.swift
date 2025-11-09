//
//  File.swift
//  request-dl
//
//  Created by Brenno de Moura on 09/11/25.
//

import Foundation

#if !(os(macOS) || os(tvOS) || os(iOS) || os(visionOS) || os(watchOS))
let NSEC_PER_SEC: UInt64 = 1_000_000_000
#endif
