//
//  SerializationUtils.swift
//  MockDuck
//
//  Created by Sebastian Celis on 9/5/18.
//  Copyright © 2018 BuzzFeed, Inc. All rights reserved.
//

import Foundation

final class SerializationUtils {

    /// The different types of files that MockDuck can read and write when mocking a request.
    enum MockFileTarget {
        case request(MockSerializableRequest)
        case requestBody(MockSerializableRequest)
        case responseData(MockSerializableRequest, MockSerializableResponse)
    }

    /// Used to determine the file name for a particular piece of data that we may want to
    /// serialize to or from disk.
    static func fileName(for type: MockFileTarget, chainSequenceIndex: Int = 0) -> String? {
        // We only construct a fileName if there is a valid path extension. The only way
        // pathExtension can be nil here is if this is a data blob that we do not support writing as
        // an associated file. In this scenario, this data is encoded and stored in the JSON itself
        // instead of as a separate, associated file.
        switch type {
        case .request(let request):
            return "\(request.serializableRequest.baseName)-\(request.requestHash).json"
        case .requestBody(let request):
            return request.serializableRequest.dataSuffix.flatMap {
                "\(request.serializableRequest.baseName)-\(request.requestHash)-request-\(chainSequenceIndex).\($0)"
            }
        case .responseData(let request, let response):
            return response.serializableResponse.dataSuffix.flatMap {
                "\(request.serializableRequest.baseName)-\(response.requestHash)-response-\(chainSequenceIndex).\($0)"
            }
        }

    }

//    private static func findNextSequenceNumber(dataFileName: String) -> Int {
//        var sequenceNumber = 0
//        guard let recordingURL = MockDuck.recordingURL else {
//            return sequenceNumber
//        }
//        var dataURL = recordingURL.appendingPathComponent(dataFileName)
//        while true {
//            if !FileManager.default.fileExists(atPath: dataURL.path) {
//                break
//            }
//            sequenceNumber += 1
//            dataURL = recordingURL.appendingPathComponent(dataFileName.replacingOccurrences(of: "seq-\(sequenceNumber)", with: "seq-\(sequenceNumber+1)"))
//        }
//        return sequenceNumber
//    }

    static func incrementFileSequence(request: URLRequest) {
        if let fileName = SerializationUtils.fileName(for: .request(request)) {
            SerializationUtils.incrementFileSequence(fileName: fileName)
        }
    }

    static var fileSequenceForName: [String : Int] = [:]

    static func fileSequence(fileName: String) -> Int {
        let sequence = fileSequenceForName[fileName]
        return sequence ?? 0
    }

    static func fileSequence(request: URLRequest) -> Int {
        guard let fileName = fileName(for: .request(request)) else {
            return 0
        }
        return fileSequence(fileName: fileName)
    }

    static func incrementFileSequence(fileName: String) {
        
        fileSequenceForName[fileName] = fileSequence(fileName: fileName) + 1
    }

}
