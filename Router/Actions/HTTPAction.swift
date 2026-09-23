//
//  HTTPAction.swift
//  TrackOSC Router (macOS)
//
//  GET or POST to a URL, with {value}, {text} and {rule} already filled in.
//  Plain http to local devices is allowed by the Info.plist ATS exception.
//

import Foundation

final class HTTPAction: Sendable {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    func send(method: String, url: String, body: String) async throws {
        guard let target = URL(string: url), target.scheme != nil else { throw ActionError.badURL(url) }
        var request = URLRequest(url: target)
        request.httpMethod = method.uppercased()
        if request.httpMethod == "POST" {
            request.httpBody = Data(body.utf8)
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            request.setValue(trimmed.hasPrefix("{") || trimmed.hasPrefix("[") ? "application/json" : "text/plain; charset=utf-8",
                             forHTTPHeaderField: "Content-Type")
        }
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ActionError.httpStatus(http.statusCode)
        }
    }
}
