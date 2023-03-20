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
        try await callRequests(1)
    }

    func testGroup() async throws {
        let results = await withTaskGroup(
            of: (Int, Result<Data, Error>).self,
            returning: [(Int, Result<Data, Error>)].self,
            body: { group in
                for index in 0 ..< 100 {
                    group.addTask {
                        do {
                            return (index, .success(try await self.sessionTask()))
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

        var request = Request(url: "https://google.com")
        request.method = "POST"
        request.body = .init(
            length: nil,
            streams: (0 ..< 10).map { index in
                {
                    InputStream(data: Data((0 ..< 1024 - (index * 100)).map { _ in
                        let element = Int.random(in: Int(UInt8.min) ... Int(UInt8.max))
                        return UInt8(element)
                    }))
                }
            }
        )

        let task = try await Session(
            provider: .shared,
            configuration: .init()
        ).request(request)

        for try await result in task.response {
            switch result {
            case .upload(let part):
                print("Uploading (\(part))")
                break
            case .download(let head, let bytes):
                print("HEAD", head)

                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                }

                print(data.count)
//                print(try await Data(bytes).count)
            }
        }

        task.shutdown()
        try await callRequests(count - 1)
    }
}

extension AnyTests {

    func sessionTask() async throws -> Data {
        let task = try await Session(
            provider: .shared,
            configuration: .init()
        ).request(.init(url: "https://google.com"))

        var data = Data()

        for try await result in task.response {
            switch result {
            case .upload:
                break
            case .download(_, let bytes):
                for try await byte in bytes {
                    data.append(byte)
                    print("[Received]", byte)
                }
//                data = try await Data(bytes)
                print(data.count)
            }
        }
        task.shutdown()

        return data
    }
}
