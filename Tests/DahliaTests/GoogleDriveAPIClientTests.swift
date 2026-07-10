import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct GoogleDriveAPIClientTests {
        @Test
        func createsGoogleDocumentWithResumableRTFUpload() async throws {
            let recorder = GoogleDriveRequestRecorder()
            let session = makeGoogleDriveRecordingSession(recorder: recorder)
            let client = GoogleDriveAPIClient(session: session)
            let rtfData = Data(#"{\rtf1 Summary}"#.utf8)

            let fileID = try await client.upsertGoogleDocument(
                accessToken: "access-token",
                fileName: "Weekly / Sync.rtf",
                data: rtfData,
                dataMimeType: "application/rtf",
                appProperties: [
                    "dahliaKind": "summary",
                    "dahliaMeetingId": "meeting-1",
                ]
            )

            #expect(fileID == "document-1")
            let requests = recorder.requests
            #expect(requests.count == 3)

            let searchRequest = requests[0]
            #expect(searchRequest.httpMethod == "GET")
            let searchURL = try #require(searchRequest.url)
            let searchQuery = try #require(
                URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "q" })?
                    .value
            )
            #expect(searchQuery.contains("dahliaMeetingId"))
            #expect(!searchQuery.contains("parents"))
            let searchQueryItems = try Dictionary(
                uniqueKeysWithValues: #require(
                    URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?.queryItems
                ).compactMap { item in
                    item.value.map { (item.name, $0) }
                }
            )
            #expect(searchQueryItems["corpora"] == "allDrives")
            #expect(searchQueryItems["includeItemsFromAllDrives"] == "true")
            #expect(searchQueryItems["supportsAllDrives"] == "true")

            let metadataRequest = requests[1]
            #expect(metadataRequest.httpMethod == "POST")
            #expect(metadataRequest.value(forHTTPHeaderField: "X-Upload-Content-Type") == "application/rtf")
            #expect(metadataRequest.value(forHTTPHeaderField: "X-Upload-Content-Length") == String(rtfData.count))
            let metadata = try JSONSerialization.jsonObject(with: #require(metadataRequest.httpBody)) as? [String: Any]
            #expect(metadata?["name"] as? String == "Weekly / Sync")
            #expect(metadata?["mimeType"] as? String == "application/vnd.google-apps.document")

            let uploadRequest = requests[2]
            #expect(uploadRequest.httpMethod == "PUT")
            #expect(uploadRequest.url?.absoluteString == "https://upload.example.com/session-1")
            #expect(uploadRequest.httpBody == rtfData)
        }
    }

    private final class GoogleDriveRequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storedRequests: [URLRequest] = []

        var requests: [URLRequest] {
            lock.withLock { storedRequests }
        }

        func record(_ request: URLRequest) -> Int {
            var recordedRequest = request
            if recordedRequest.httpBody == nil,
               let bodyStream = request.httpBodyStream {
                recordedRequest.httpBody = Self.read(bodyStream)
            }
            return lock.withLock {
                storedRequests.append(recordedRequest)
                return storedRequests.count
            }
        }

        private static func read(_ stream: InputStream) -> Data {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            stream.open()
            defer { stream.close() }

            var data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4096)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }

    private func makeGoogleDriveRecordingSession(recorder: GoogleDriveRequestRecorder) -> URLSession {
        GoogleDriveRecordingURLProtocol.recorder = recorder
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GoogleDriveRecordingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private final class GoogleDriveRecordingURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var recorder: GoogleDriveRequestRecorder?

        // swiftlint:disable:next static_over_final_class
        override class func canInit(with _: URLRequest) -> Bool {
            true
        }

        // swiftlint:disable:next static_over_final_class
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let requestIndex = Self.recorder?.record(request) ?? 0
            let response: HTTPURLResponse
            let data: Data

            switch requestIndex {
            case 1:
                response = makeResponse()
                data = Data(#"{"files":[]}"#.utf8)
            case 2:
                response = makeResponse(headers: ["Location": "https://upload.example.com/session-1"])
                data = Data()
            default:
                response = makeResponse()
                data = Data(#"{"id":"document-1"}"#.utf8)
            }

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private func makeResponse(headers: [String: String] = [:]) -> HTTPURLResponse {
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: headers
                  ) else {
                fatalError("Could not create test HTTP response")
            }
            return response
        }
    }
#endif
