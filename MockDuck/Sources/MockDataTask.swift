//
//  MockDataTask.swift
//  MockDuck
//
//  Created by Peter Walters on 3/20/18.
//  Copyright © 2018 BuzzFeed, Inc. All rights reserved.
//

import Foundation

/// A URLSessionDataTask subclass that attempts to return a cached response from disk, when
/// possible. When it is unable to load a response from disk, it can optionally use a fallback
/// URLSession to handle the request normally.
final class MockDataTask: URLSessionDataTask {

    typealias TaskCompletion = (MockRequestResponse?, Error?) -> Void

    enum ErrorType: Error {
        case unknown
    }

    private let request: URLRequest
    private let completion: TaskCompletion
    private var fallbackTask: URLSessionDataTask?

    init(request: URLRequest, completion: @escaping TaskCompletion) {
        self.request = request
        self.completion = completion
        super.init()
    }

    // On task execution, look for a saved request or kick off the fallback request.
    override func resume() {
        let fileSequence = SerializationUtils.fileSequence(request: request)
        if let sequence = MockDuck.mockBundle.loadRequestResponse(for: request, fileSequence: fileSequence) {
            SerializationUtils.incrementFileSequence(request: request)
            // The request is found. Load the MockRequestResponse and call the completion/finish
            // with the stored data.
            completion(sequence, nil)
        } else if MockDuck.shouldFallbackToNetwork {
            // The request isn't found but we should fallback to the network. Kick off a task with
            // the fallback URLSession.
            fallbackTask = MockDuck.fallbackSession.dataTask(with: request, completionHandler: { data, response, error in
                if let error = error {
                    self.completion(nil, error)
                } else if let response = response {
                    let requestResponse = MockRequestResponse(request: self.request, response: response, responseData: data)
                    MockDuck.mockBundle.record(requestResponse: requestResponse)
                    //assertRequestIsLoadable(request: self.request, response: response, responseData: data)
                    SerializationUtils.incrementFileSequence(request: self.request)
                    self.completion(requestResponse, nil)
                } else {
                    self.completion(nil, ErrorType.unknown)
                }

                self.fallbackTask = nil
            })
            fallbackTask?.resume()
        } else {
            MockDuck.mockDuckReplayRequestNotFound(request)
            // The request isn't found and we shouldn't fallback to the network. Return a
            // well-crafted error in the completion.
            let fileName = SerializationUtils.fileName(for: .request(request))
            print(fileName)
            let requestURL = request.url
            print(requestURL)
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
            completion(nil, error)
        }
    }

    override func cancel() {
        fallbackTask?.cancel()
        fallbackTask = nil
    }
}

private func assertRequestIsLoadable(request: URLRequest, response: URLResponse, responseData: Data?) {
    let fileSequence = SerializationUtils.fileSequence(request: request)

    // Set temporarily to allow for testing the loading of the request
    MockDuck.loadingURL = MockDuck.recordingURL

    guard let loadedRequestResponse = MockDuck.mockBundle.loadRequestResponse(for: request, fileSequence: fileSequence) else {
        MockDuck.loadingURL = nil
        let fileName = SerializationUtils.fileName(for: .request(request), chainSequenceIndex: fileSequence)
        let allFiles = FileManager.default.subpaths(atPath: MockDuck.recordingURL!.path)
        let message =
        """
        \(#file):\(#function)
        Mock recording failed for
        files path = \(MockDuck.recordingURL!.path)
        all files = \(allFiles)
        file name: \(fileName)
        file sequence: \(fileSequence)
        request: \(request.debugDescription)
        response: \(response.debugDescription)
        data: \(responseData?.prettyPrintedJSONString)
        """
        print(message)
        return
    }

    let requestIsEqual = request == loadedRequestResponse.request
    if !requestIsEqual {
        print("FAILED: requestIsEqual")
    }
    let requestHashIsEqual = request.requestHash == loadedRequestResponse.requestHash
    if !requestHashIsEqual {
        print("FAILED: requestHashIsEqual")
    }
    let responseIsEqual = response.isEqual(loadedRequestResponse.response)
    if !responseIsEqual {
        print("FAILED: responseIsEqual")
    }
    let responseDataIsEqual = responseData == loadedRequestResponse.responseData
    if !responseDataIsEqual {
        print("FAILED: responseDataIsEqual")
    }
    MockDuck.loadingURL = nil
    //    let serializableRequestDataIsEqual = request.serializableRequest == loadedRequestResponse.serializableRequest
}
