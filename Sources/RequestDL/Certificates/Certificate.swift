/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A representation of a certificate that is loaded from a specified bundle.

 A certificate is a digital file used to establish a secure connection between two parties
 over the internet. This struct represents a certificate that is loaded from a specified bundle.

 You can use this struct to create a secure connection with a server using SSL pinning.
 The certificate is used to verify that the server is legitimate and prevent man-in-the-middle attacks.

 Example:

 ```swift
 let bundle = Bundle.main
 let certificate = Certificate("example.cer", in: bundle)
 ```
 */
public struct Certificate {

    let name: String
    let bundle: Bundle

    /**
     Initializes a certificate object with the specified name and bundle.

     - Parameters:
        - name: The name of the certificate file.
        - bundle: The bundle containing the certificate file.
     */
    public init(_ name: String, in bundle: Bundle) {
        self.name = name
        self.bundle = bundle
    }
}
