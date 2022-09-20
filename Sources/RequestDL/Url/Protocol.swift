import Foundation

/**
 Defines constants for the communication protocol.

 Constants are used in URL initialization to define which communication
 protocol will be used for transmission.
 */
public enum Protocol: String {

    /// Used to make HTTP requests
    case http

    /// Used to make HTTPS requests
    case https
}
