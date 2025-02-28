//
//  MockDuck.swift
//  MockDuck
//
//  Created by Peter Walters on 3/20/18.
//  Copyright © 2018 BuzzFeed, Inc. All rights reserved.
//

import Foundation
import os

/// A delegate protocol that can be used to modify how MockDuck functions.
public protocol MockDuckDelegate: class {

    /// A hook that allows one to normalize a request before it is turned into a hash that uniquely
    /// identifies it on the filesystem. By default, the entire request URL and the request body
    /// are used to create a unique request hash. It may be useful to remove some query parameters
    /// here or clear out the body so that multiple similar requests all hash to the same location
    /// on disk.
    ///
    /// - Parameter request: The request to normalize
    /// - Returns: The normalized request
    func normalizedRequest(for request: URLRequest) -> URLRequest

    func requestCanInit(with request: URLRequest) -> Bool
}

/// Public-facing errors that MockDuck can throw.
public enum MockDuckError: Error {

    /// HTTPURLResponse has a failable initializer. If MockDuck unexpectedly encounter that, this
    /// error will be thrown.
    case unableToInitializeURLResponse
}

// MARK: -

/// MockDuck top level class for configuring the framework. This class is responsible for
/// registering MockDuck as a URLProtocol that allows it to intercept network traffic.
public final class MockDuck {

    // MARK: - Public

    /// A delegate that allows a class to hook into and modify how MockDuck behaves.
    public static weak var delegate: MockDuckDelegate? {
        willSet {
            checkConfigureMockDuck()
        }
    }
    
    public static func requestCanInit(with request: URLRequest) -> Bool {
        return delegate?.requestCanInit(with: request) ?? true
    }

    /// By default, MockDuck is enabled, even though it does nothing until configured by setting
    /// `loadingURL`, `recordingURL`, or by registering a request mock. This is here, however, to allow
    /// developers to quickly disable MockDuck by setting this to `false`.
    public static var enabled = true {
        willSet {
            checkConfigureMockDuck()
        }
    }

    /// By default, MockDuck will fallback to making a network request if the request can not be
    /// loaded from `loadingURL` or if the request can not be handled by a registered request mock.
    /// Set this to `false` to force an error that resembles what `URLSession` provides when the
    /// network is unreachable.
    public static var shouldFallbackToNetwork = true {
        willSet {
            checkConfigureMockDuck()
        }
    }

    /// When MockDuck falls back to making a normal network request, it will use a URLSession
    /// configured with this object. You can hook in here to modify how these fallback requests
    /// are made.
    public static var fallbackSessionConfiguration = URLSessionConfiguration.default {
        willSet {
            checkConfigureMockDuck()
        }
        didSet {
            fallbackSession = URLSession(configuration: fallbackSessionConfiguration)
        }
    }

    /// The location where MockDuck will attempt to look for network requests that have been saved
    /// to disk.
    public static var loadingURL: URL? {
        willSet {
            checkConfigureMockDuck()
        }
        didSet {
            mockBundle.loadingURL = loadingURL

            if let loadingURL = loadingURL {
                os_log("Loading network requests from: %@", log: log, type: .info, loadingURL.path)
            } else {
                os_log("No longer loading network requests from disk", log: log, type: .info)
            }
        }
    }

    /// The location where MockDuck should attempt to save network requests that occur. This is a
    /// useful way to record a session of network activity to disk which is then used in the future
    /// by pointing to this same data using `loadingURL`.
    public static var recordingURL: URL? {
        willSet {
            checkConfigureMockDuck()
        }
        didSet {
            mockBundle.recordingURL = recordingURL

            if let recordingURL = recordingURL {
                os_log("Recording network requests to: %@", log: log, type: .info, recordingURL.path)
            } else {
                os_log("No longer recording network requests", log: log, type: .info)
            }
        }
    }

    // MARK: - Providing Request Handlers

    public typealias RequestHandler = (URLRequest) -> MockResponse?

    /// This function allows one to hook into MockDuck by allowing the caller to override any
    /// request with a mock response. This is most often used in unit tests to mock out expected
    /// requests so that the network isn't actually hit, introducing instability to the test.
    ///
    /// - Parameter handler: The handler to register. It receives a single parameter being the
    /// URLRequest that is about to be made. This block should return `nil` to do nothing with that
    /// request. Otherwise, it should return a `MockResponse` object that describes the full
    /// response that should be used for that request.
    public static func registerRequestHandler(_ handler: @escaping RequestHandler) {
        checkConfigureMockDuck()
        mockBundle.registerRequestHandler(handler)
    }

    /// Quickly unregister all request handlers that were registered by calling
    /// `registerRequestHandler`. You generally want to call this in the `tearDown` method of your
    /// unit tests.
    public static func unregisterAllRequestHandlers() {
        mockBundle.unregisterAllRequestHandlers()
    }

    // MARK: - Internal Use Only

    /// MockDuck uses this to log all of its messages.
    internal static let log = OSLog(subsystem: "com.buzzfeed.MockDuck", category: "default")

    /// This is the session MockDuck will fallback to using if the mocked request is not found and
    /// if `MockDuck.shouldFallbackToNetwork` is `true`.
    internal private(set) static var fallbackSession = URLSession.shared

    // This is the URLSession subclass that we use to handle all mocked network requests.
    internal private(set) static var mockSession = MockSession()

    /// This is the object responsible for loading cached requests from disks as well as recording
    /// new requests to disk.
    internal private(set) static var mockBundle = MockBundle()

    // MARK: - Private Configuration

    private static var isConfigured = false

    private static func checkConfigureMockDuck() {
        guard !isConfigured else { return }

        // Register our URLProtocol class
        URLProtocol.registerClass(MockURLProtocol.self)

        // Swizzle the default `URLSessionConfiguration` getters so that MockDuck automatically
        // works with other URLSessions.
        swizzleURLSessionConfiguration()

        isConfigured = true
    }

    private static func swizzleURLSessionConfiguration() {
        let sessionConfigurationClass = URLSessionConfiguration.self

        if
            let originalMethod = class_getClassMethod(
                sessionConfigurationClass,
                #selector(getter: URLSessionConfiguration.default)),
            let swizzledMethod = class_getClassMethod(
                sessionConfigurationClass,
                #selector(getter: URLSessionConfiguration.mockDuck_defaultSessionConfiguration))
        {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }

        if
            let originalMethod = class_getClassMethod(
                sessionConfigurationClass,
                #selector(getter: URLSessionConfiguration.ephemeral)),
            let swizzledMethod = class_getClassMethod(
                sessionConfigurationClass,
                #selector(getter: URLSessionConfiguration.mockDuck_ephemeralSessionConfiguration))
        {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    /// Prepare a `URLSessionConfiguration` so that MockDuck can properly intercept request made by
    /// the resulting session. MockDuck swizzles `URLSessionConfiguration.default` and
    /// `URLSessionConfiguration.ephemeral` so that these configurations are properly configured by
    /// default.
    ///
    /// - Parameter configuration: The URL session configuration to prepare for MockDuck. Any URL
    /// session that uses this configuration will be properly setup for MockDuck interception.
    fileprivate static func prepareSessionConfiguration(_ configuration: URLSessionConfiguration) {
        var protocolClasses = configuration.protocolClasses ?? []
        protocolClasses.insert(MockURLProtocol.self, at: 0)
        configuration.protocolClasses = protocolClasses
    }
}

extension URLSessionConfiguration {
    @objc dynamic static var mockDuck_defaultSessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.mockDuck_defaultSessionConfiguration
        MockDuck.prepareSessionConfiguration(configuration)
        return configuration
    }

    @objc dynamic static var mockDuck_ephemeralSessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.mockDuck_ephemeralSessionConfiguration
        MockDuck.prepareSessionConfiguration(configuration)
        return configuration
    }
}
