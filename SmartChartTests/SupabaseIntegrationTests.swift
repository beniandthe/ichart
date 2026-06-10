import XCTest

final class SupabaseIntegrationTests: XCTestCase {
    func testLiveSupabaseProfileChartSnapshotAndDeleteTombstoneFlow() async throws {
        let configuration = try SupabaseIntegrationConfiguration.current()
        let client = SupabaseRESTClient(configuration: configuration)
        let testID = UUID().uuidString.lowercased()
        let email = "smart-chart-\(testID)@example.com"
        let password = "SmartChart-\(testID)-Pass1!"
        let session = try await client.signUp(email: email, password: password)
        let chartID = UUID().uuidString.lowercased()
        let snapshotID = UUID().uuidString.lowercased()
        let timestamp = ISO8601DateFormatter.smartChartIntegration.string(from: Date())

        try await client.upsertProfile(
            userID: session.userID,
            accessToken: session.accessToken,
            email: email,
            phone: "+15555550123",
            mailingAddress: "123 iChart Test Lane",
            paymentSummary: "Processor customer reference only"
        )

        let profileRows = try await client.rows(
            path: "profiles",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(session.userID)"),
                URLQueryItem(name: "select", value: "*")
            ],
            accessToken: session.accessToken
        )
        let profile: [String: Any] = try XCTUnwrap(profileRows.first)
        XCTAssertEqual(profile["email"] as? String, email)
        XCTAssertEqual(profile["phone"] as? String, "+15555550123")
        XCTAssertNil(profile["card_number"])

        try await client.insertChartDocument(
            chartID: chartID,
            userID: session.userID,
            accessToken: session.accessToken,
            title: "Integration Chart",
            timestamp: timestamp
        )
        try await client.insertChartSnapshot(
            snapshotID: snapshotID,
            chartID: chartID,
            userID: session.userID,
            accessToken: session.accessToken,
            timestamp: timestamp
        )
        try await client.updateChartLatestSnapshot(
            chartID: chartID,
            snapshotID: snapshotID,
            accessToken: session.accessToken,
            timestamp: timestamp
        )

        let chartRows = try await client.rows(
            path: "chart_documents",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(chartID)"),
                URLQueryItem(name: "select", value: "*")
            ],
            accessToken: session.accessToken
        )
        let chart: [String: Any] = try XCTUnwrap(chartRows.first)
        XCTAssertEqual(chart["latest_snapshot_id"] as? String, snapshotID)
        XCTAssertEqual(integralValue(chart["remote_revision"]), 1)

        try await client.tombstoneChart(
            chartID: chartID,
            accessToken: session.accessToken,
            timestamp: timestamp
        )

        let tombstoneRows = try await client.rows(
            path: "chart_documents",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(chartID)"),
                URLQueryItem(name: "select", value: "id,deleted_at,latest_snapshot_id,remote_revision")
            ],
            accessToken: session.accessToken
        )
        let tombstone: [String: Any] = try XCTUnwrap(tombstoneRows.first)
        XCTAssertNotNil(tombstone["deleted_at"] as? String)
        XCTAssertTrue(tombstone["latest_snapshot_id"] is NSNull)
        XCTAssertEqual(integralValue(tombstone["remote_revision"]), 2)
    }
}

private func integralValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
        return value
    }
    if let value = value as? NSNumber {
        return value.intValue
    }
    return nil
}

private struct SupabaseIntegrationConfiguration {
    let baseURL: URL
    let publishableKey: String

    var isLocalSupabase: Bool {
        baseURL.host == "127.0.0.1" || baseURL.host == "localhost"
    }

    var mailpitBaseURL: URL? {
        guard isLocalSupabase else {
            return nil
        }

        return URL(string: "http://127.0.0.1:54324")
    }

    static func current() throws -> SupabaseIntegrationConfiguration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SMART_CHART_SUPABASE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set SMART_CHART_SUPABASE_INTEGRATION=1 to run live Supabase integration tests.")
        }

        guard let urlString = environment["SUPABASE_URL"],
              let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw XCTSkip("SUPABASE_URL is required for live Supabase integration tests.")
        }

        let key = environment["SUPABASE_PUBLISHABLE_KEY"]
            ?? environment["SUPABASE_ANON_KEY"]
        guard let key,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("SUPABASE_PUBLISHABLE_KEY or SUPABASE_ANON_KEY is required.")
        }

        return SupabaseIntegrationConfiguration(baseURL: url, publishableKey: key)
    }
}

private struct SupabaseIntegrationSession {
    let userID: String
    let accessToken: String
}

private struct SupabaseRESTClient {
    let configuration: SupabaseIntegrationConfiguration

    func signUp(email: String, password: String) async throws -> SupabaseIntegrationSession {
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        let response = try await request(
            path: "auth/v1/signup",
            method: "POST",
            accessToken: nil,
            body: body
        )

        if let session = session(from: response) {
            return session
        }

        guard configuration.isLocalSupabase else {
            throw XCTSkip("Supabase sign-up requires email verification before integration tests can continue.")
        }

        try await confirmLocalSignupEmail(email: email)
        return try await signIn(email: email, password: password)
    }

    func signIn(email: String, password: String) async throws -> SupabaseIntegrationSession {
        let response = try await request(
            path: "auth/v1/token",
            method: "POST",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            accessToken: nil,
            body: [
                "email": email,
                "password": password
            ]
        )

        guard let session = session(from: response) else {
            throw XCTSkip("Supabase sign-in did not return a session.")
        }

        return session
    }

    func upsertProfile(
        userID: String,
        accessToken: String,
        email: String,
        phone: String,
        mailingAddress: String,
        paymentSummary: String
    ) async throws {
        _ = try await requestArray(
            path: "rest/v1/profiles",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=representation",
            body: [
                "id": userID,
                "email": email,
                "phone": phone,
                "mailing_address": mailingAddress,
                "payment_summary": paymentSummary
            ]
        )
    }

    func insertChartDocument(
        chartID: String,
        userID: String,
        accessToken: String,
        title: String,
        timestamp: String
    ) async throws {
        _ = try await requestArray(
            path: "rest/v1/chart_documents",
            method: "POST",
            accessToken: accessToken,
            prefer: "return=representation",
            body: [
                "id": chartID,
                "owner_id": userID,
                "title": title,
                "layout_style": "simpleChordSheet",
                "remote_revision": 1,
                "client_updated_at": timestamp
            ]
        )
    }

    func insertChartSnapshot(
        snapshotID: String,
        chartID: String,
        userID: String,
        accessToken: String,
        timestamp: String
    ) async throws {
        _ = try await requestArray(
            path: "rest/v1/chart_snapshots",
            method: "POST",
            accessToken: accessToken,
            prefer: "return=representation",
            body: [
                "id": snapshotID,
                "chart_id": chartID,
                "owner_id": userID,
                "version": 1,
                "client_updated_at": timestamp,
                "chart_json": [
                    "id": chartID,
                    "title": "Integration Chart",
                    "layoutStyle": "simpleChordSheet",
                    "updatedAt": Date().timeIntervalSinceReferenceDate
                ]
            ]
        )
    }

    func updateChartLatestSnapshot(
        chartID: String,
        snapshotID: String,
        accessToken: String,
        timestamp: String
    ) async throws {
        _ = try await requestArray(
            path: "rest/v1/chart_documents",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(chartID)")],
            accessToken: accessToken,
            prefer: "return=representation",
            body: [
                "latest_snapshot_id": snapshotID,
                "remote_revision": 1,
                "client_updated_at": timestamp,
                "last_snapshot_at": timestamp
            ]
        )
    }

    func tombstoneChart(chartID: String, accessToken: String, timestamp: String) async throws {
        _ = try await requestArray(
            path: "rest/v1/chart_documents",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(chartID)")],
            accessToken: accessToken,
            prefer: "return=representation",
            body: [
                "deleted_at": timestamp,
                "latest_snapshot_id": NSNull(),
                "remote_revision": 2,
                "client_updated_at": timestamp
            ]
        )
    }

    func rows(
        path: String,
        queryItems: [URLQueryItem],
        accessToken: String
    ) async throws -> [[String: Any]] {
        try await requestArray(
            path: "rest/v1/\(path)",
            method: "GET",
            queryItems: queryItems,
            accessToken: accessToken,
            body: nil
        )
    }

    private func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        accessToken: String?,
        prefer: String? = nil,
        body: [String: Any]?
    ) async throws -> [String: Any] {
        let data = try await requestData(
            path: path,
            method: method,
            queryItems: queryItems,
            accessToken: accessToken,
            prefer: prefer,
            body: body
        )

        guard !data.isEmpty else {
            return [:]
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func requestArray(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        accessToken: String?,
        prefer: String? = nil,
        body: [String: Any]?
    ) async throws -> [[String: Any]] {
        let data = try await requestData(
            path: path,
            method: method,
            queryItems: queryItems,
            accessToken: accessToken,
            prefer: prefer,
            body: body
        )

        guard !data.isEmpty else {
            return []
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func requestData(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        accessToken: String?,
        prefer: String?,
        body: [String: Any]?
    ) async throws -> Data {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        var request = URLRequest(url: try XCTUnwrap(components?.url))
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(configuration.publishableKey)", forHTTPHeaderField: "Authorization")
        }
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "<empty response>"
            XCTFail("Supabase request \(method) \(path) failed with \(statusCode): \(message)")
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func session(from response: [String: Any]) -> SupabaseIntegrationSession? {
        guard let accessToken = response["access_token"] as? String else {
            return nil
        }

        let user = response["user"] as? [String: Any]
        let userID = user?["id"] as? String ?? response["id"] as? String
        guard let userID else {
            return nil
        }

        return SupabaseIntegrationSession(userID: userID, accessToken: accessToken)
    }

    private func confirmLocalSignupEmail(email: String) async throws {
        guard let confirmationURL = try await localSignupConfirmationURL(email: email) else {
            throw XCTSkip("Local Supabase did not send a signup confirmation email.")
        }

        try await requestConfirmationLink(confirmationURL)
    }

    private func localSignupConfirmationURL(email: String) async throws -> URL? {
        for _ in 0..<20 {
            if let confirmationURL = try await latestLocalSignupConfirmationURL(email: email) {
                return confirmationURL
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        return nil
    }

    private func latestLocalSignupConfirmationURL(email: String) async throws -> URL? {
        guard let mailpitBaseURL = configuration.mailpitBaseURL else {
            return nil
        }

        let data = try await URLSession.shared.data(from: mailpitBaseURL.appendingPathComponent("api/v1/messages")).0
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = (payload["messages"] as? [[String: Any]]) ?? []

        for message in messages {
            guard let subject = message["Subject"] as? String,
                  subject.localizedCaseInsensitiveContains("confirm"),
                  messageIsAddressed(to: email, message: message),
                  let id = message["ID"] as? String
            else {
                continue
            }

            let detailData = try await URLSession.shared
                .data(from: mailpitBaseURL.appendingPathComponent("api/v1/message/\(id)")).0
            let detail = try XCTUnwrap(JSONSerialization.jsonObject(with: detailData) as? [String: Any])
            let text = (detail["Text"] as? String) ?? (detail["HTML"] as? String) ?? ""
            if let url = firstVerificationURL(in: text) {
                return url
            }
        }

        return nil
    }

    private func messageIsAddressed(to email: String, message: [String: Any]) -> Bool {
        let recipients = (message["To"] as? [[String: Any]]) ?? []
        return recipients.contains { recipient in
            (recipient["Address"] as? String)?.caseInsensitiveCompare(email) == .orderedSame
        }
    }

    private func firstVerificationURL(in text: String) -> URL? {
        let pattern = #"http://127\.0\.0\.1:54321/auth/v1/verify\?[^\s\)"]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else {
            return nil
        }

        let candidate = text[range].replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: candidate)
    }

    private func requestConfirmationLink(_ url: URL) async throws {
        let delegate = SupabaseNoRedirectDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let (_, response) = try await session.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        XCTAssertTrue(
            (200..<400).contains(statusCode),
            "Local Supabase confirmation failed with \(statusCode)."
        )
    }
}

private extension ISO8601DateFormatter {
    static let smartChartIntegration: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private final class SupabaseNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
