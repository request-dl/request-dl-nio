//
//  File.swift
//  
//
//  Created by Brenno on 18/03/23.
//

import XCTest
@testable import RequestDLInternals

class AnyTests: XCTestCase {

    func testSome() async throws {
        try await callRequests(10)
    }

    func testGroup() async throws {
        let results = await withTaskGroup(
            of: (Int, Result<Data, Error>).self,
            returning: [(Int, Result<Data, Error>)].self,
            body: { group in
                for index in 0 ..< 100 {
                    group.addTask {
                        do {
                            print(index)
                            let results = try await Session(
                                provider: .shared,
                                configuration: .init()
                            ).request(.init(url: "https://google.com"))

                            var data = Data()

                            for try await result in AsyncResponse(response: results) {
                                switch result {
                                case .upload:
                                    break
                                case .download(_, let bytes):
                                    for try await byte in bytes {
                                        data.append(byte)
                                    }
                                }
                            }

                            return (index, .success(data))
                        } catch {
                            return (index, .failure(error))
                        }
                    }
                }

                var results = [(Int, Result<Data, Error>)]()

                for await (index, result) in group {
                    results.append((index, result))
                }

                return results
            }
        )

        print("[Here]", results.map(\.0))
    }
}

extension AnyTests {

    func callRequests(_ count: Int) async throws {
        if count <= .zero {
            return
        }

        let results = try await Session(
            provider: .shared,
            configuration: .init()
        ).request(.init(url: "https://google.com"))

        for try await result in AsyncResponse(response: results) {
            switch result {
            case .upload(let part):
//                print("Uploading (\(part))")
                break
            case .download(let head, let bytes):
//                print("HEAD", head)

                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                }

//                print(data.count)
            }
        }

//        try await callRequests(count - 1)
    }
}
