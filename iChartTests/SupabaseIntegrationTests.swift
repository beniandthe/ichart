import XCTest

final class SupabaseIntegrationTests: XCTestCase {
    func testLiveSupabaseProfileChartSnapshotAndDeleteTombstoneFlow() async throws {
        let configuration = try SupabaseIntegrationConfiguration.current()
        guard let adminKey = configuration.adminKey else {
            throw XCTSkip("SUPABASE_SERVICE_ROLE_KEY is required for Pro cloud integration tests.")
        }

        let client = SupabaseRESTClient(configuration: configuration)
        let testID = UUID().uuidString.lowercased()
        let email = "ichart-\(testID)@example.com"
        let password = "iChart-\(testID)-Pass1!"
        let session = try await client.signUp(email: email, password: password)
        let chartID = UUID().uuidString.lowercased()
        let snapshotID = UUID().uuidString.lowercased()
        let timestamp = ISO8601DateFormatter.smartChartIntegration.string(from: Date())

        try await client.assertProfilePaymentSummaryWriteRejected(
            userID: session.userID,
            accessToken: session.accessToken,
            paymentSummary: "Processor customer reference only"
        )
        try await client.grantActiveProEntitlement(
            userID: session.userID,
            adminKey: adminKey
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

    func testLiveSupabaseForumPublishVoteCommentReportAndStorageFlow() async throws {
        let configuration = try SupabaseIntegrationConfiguration.current()
        guard let adminKey = configuration.adminKey else {
            throw XCTSkip("SUPABASE_SERVICE_ROLE_KEY is required for Pro forum integration tests.")
        }

        let client = SupabaseRESTClient(configuration: configuration)
        let testID = UUID().uuidString.lowercased()
        let proEmail = "ichart-forum-pro-\(testID)@example.com"
        let basicEmail = "ichart-forum-basic-\(testID)@example.com"
        let password = "iChart-\(testID)-Forum1!"
        var proUserID: String?
        var basicUserID: String?
        var storagePath: String?

        do {
            proUserID = try await client.adminCreateConfirmedUser(
                email: proEmail,
                password: password,
                firstName: "Forum",
                lastName: "Pro",
                adminKey: adminKey
            )
            basicUserID = try await client.adminCreateConfirmedUser(
                email: basicEmail,
                password: password,
                firstName: "Forum",
                lastName: "Basic",
                adminKey: adminKey
            )

            let proSession = try await client.signIn(email: proEmail, password: password)
            let basicSession = try await client.signIn(email: basicEmail, password: password)
            XCTAssertEqual(proSession.userID, proUserID)
            XCTAssertEqual(basicSession.userID, basicUserID)

            try await client.grantActiveProEntitlement(
                userID: proSession.userID,
                adminKey: adminKey
            )

            let basicSongID = UUID().uuidString.lowercased()
            do {
                try await client.insertForumSong(
                    songID: basicSongID,
                    userID: basicSession.userID,
                    accessToken: basicSession.accessToken,
                    title: "Denied Forum Tune",
                    artist: "Denied Artist"
                )
                XCTFail("Inactive Basic account unexpectedly inserted forum song metadata.")
            } catch let error as SupabaseRequestError {
                XCTAssertTrue(
                    [401, 403].contains(error.statusCode),
                    "Expected Basic forum denial, got \(error.statusCode): \(error.message)"
                )
            }

            let songID = UUID().uuidString.lowercased()
            let postID = UUID().uuidString.lowercased()
            let voteID = UUID().uuidString.lowercased()
            let commentID = UUID().uuidString.lowercased()
            let reportID = UUID().uuidString.lowercased()
            let path = "\(proSession.userID)/\(postID).pdf"
            storagePath = path

            try await client.uploadForumPDF(
                path: path,
                accessToken: proSession.accessToken,
                data: Data("%PDF-1.4\n% iChart forum integration\n%%EOF\n".utf8)
            )
            try await client.insertForumSong(
                songID: songID,
                userID: proSession.userID,
                accessToken: proSession.accessToken,
                title: "Forum Integration Tune",
                artist: "iChart QA"
            )
            try await client.insertForumPost(
                postID: postID,
                songID: songID,
                userID: proSession.userID,
                accessToken: proSession.accessToken,
                chartTitle: "Forum Integration Chart",
                storagePath: path
            )

            let pendingPostRows = try await client.rows(
                path: "forum_chart_posts",
                queryItems: [
                    URLQueryItem(name: "id", value: "eq.\(postID)"),
                    URLQueryItem(name: "select", value: "id,status")
                ],
                accessToken: proSession.accessToken
            )
            XCTAssertEqual(pendingPostRows.first?["status"] as? String, "pending")

            try await client.approveForumPost(postID: postID, adminKey: adminKey)

            let downloadedPDF = try await client.downloadForumPDF(
                path: path,
                accessToken: proSession.accessToken
            )
            XCTAssertTrue(downloadedPDF.starts(with: Data("%PDF".utf8)))

            try await client.insertForumVote(
                voteID: voteID,
                postID: postID,
                userID: proSession.userID,
                accessToken: proSession.accessToken,
                value: 1
            )
            try await client.insertForumComment(
                commentID: commentID,
                postID: postID,
                userID: proSession.userID,
                accessToken: proSession.accessToken,
                body: "Clean forum integration comment."
            )
            try await client.insertForumPostReport(
                reportID: reportID,
                postID: postID,
                userID: proSession.userID,
                accessToken: proSession.accessToken
            )

            let postRows = try await client.rows(
                path: "forum_chart_posts",
                queryItems: [
                    URLQueryItem(name: "id", value: "eq.\(postID)"),
                    URLQueryItem(name: "select", value: "id,vote_up_count,vote_down_count,report_count,status,creator_display_name,pdf_storage_path,pdf_provenance_status")
                ],
                accessToken: proSession.accessToken
            )
            let post: [String: Any] = try XCTUnwrap(postRows.first)
            XCTAssertEqual(integralValue(post["vote_up_count"]), 1)
            XCTAssertEqual(integralValue(post["vote_down_count"]), 0)
            XCTAssertEqual(integralValue(post["report_count"]), 1)
            XCTAssertEqual(post["status"] as? String, "published")
            XCTAssertEqual(post["creator_display_name"] as? String, "Forum Pro")
            XCTAssertEqual(post["pdf_storage_path"] as? String, path)
            XCTAssertEqual(post["pdf_provenance_status"] as? String, "validated")

            let comments = try await client.rows(
                path: "forum_comments",
                queryItems: [
                    URLQueryItem(name: "post_id", value: "eq.\(postID)"),
                    URLQueryItem(name: "select", value: "id,body,report_count")
                ],
                accessToken: proSession.accessToken
            )
            XCTAssertEqual(comments.count, 1)
            XCTAssertEqual(comments.first?["body"] as? String, "Clean forum integration comment.")
        } catch {
            await client.cleanupForumIntegrationUser(
                userID: proUserID,
                storagePath: storagePath,
                adminKey: adminKey
            )
            await client.cleanupForumIntegrationUser(
                userID: basicUserID,
                storagePath: nil,
                adminKey: adminKey
            )
            throw error
        }

        await client.cleanupForumIntegrationUser(
            userID: proUserID,
            storagePath: storagePath,
            adminKey: adminKey
        )
        await client.cleanupForumIntegrationUser(
            userID: basicUserID,
            storagePath: nil,
            adminKey: adminKey
        )
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
    let adminKey: String?

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
        guard environment["ICHART_SUPABASE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set ICHART_SUPABASE_INTEGRATION=1 to run live Supabase integration tests.")
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

        let adminKeyCandidate = environment["SUPABASE_SERVICE_ROLE_KEY"]
            ?? environment["SUPABASE_SECRET_KEY"]
        let adminKey = adminKeyCandidate?.trimmingCharacters(in: .whitespacesAndNewlines)

        return SupabaseIntegrationConfiguration(
            baseURL: url,
            publishableKey: key,
            adminKey: adminKey?.isEmpty == false ? adminKey : nil
        )
    }
}

private struct SupabaseIntegrationSession {
    let userID: String
    let accessToken: String
}

private struct SupabaseRESTClient {
    let configuration: SupabaseIntegrationConfiguration

    func adminCreateConfirmedUser(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
        adminKey: String
    ) async throws -> String {
        let response = try await request(
            path: "auth/v1/admin/users",
            method: "POST",
            accessToken: adminKey,
            body: [
                "email": email,
                "password": password,
                "email_confirm": true,
                "user_metadata": [
                    "first_name": firstName,
                    "last_name": lastName
                ]
            ]
        )

        return try XCTUnwrap(response["id"] as? String)
    }

    func deleteAuthUser(userID: String, adminKey: String) async throws {
        _ = try await requestData(
            path: "auth/v1/admin/users/\(userID)",
            method: "DELETE",
            queryItems: [],
            accessToken: adminKey,
            prefer: nil,
            body: nil
        )
    }

    func grantActiveProEntitlement(userID: String, adminKey: String) async throws {
        let now = Date()
        let expiry = now.addingTimeInterval(3_600)
        _ = try await requestArray(
            path: "rest/v1/subscriptions",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "owner_id")],
            accessToken: adminKey,
            prefer: "resolution=merge-duplicates,return=representation",
            body: [
                "owner_id": userID,
                "plan": "studioSubscription",
                "status": "active",
                "provider": "manual",
                "entitlement_expires_at": ISO8601DateFormatter.smartChartIntegration.string(from: expiry),
                "revoked_at": NSNull(),
                "last_verified_at": ISO8601DateFormatter.smartChartIntegration.string(from: now)
            ]
        )
    }

    func signUp(email: String, password: String) async throws -> SupabaseIntegrationSession {
        do {
            return try await requestSignUp(email: email, password: password)
        } catch let error as SupabaseRequestError
            where configuration.isLocalSupabase && error.isEmailSendRateLimit {
            try await Task.sleep(nanoseconds: 65_000_000_000)
            return try await requestSignUp(email: email, password: password)
        }
    }

    private func requestSignUp(email: String, password: String) async throws -> SupabaseIntegrationSession {
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

    func assertProfilePaymentSummaryWriteRejected(
        userID: String,
        accessToken: String,
        paymentSummary: String
    ) async throws {
        do {
            _ = try await requestArray(
                path: "rest/v1/profiles",
                method: "POST",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                accessToken: accessToken,
                prefer: "resolution=merge-duplicates,return=representation",
                body: [
                    "id": userID,
                    "payment_summary": paymentSummary
                ]
            )
            XCTFail("Client profile writes must not update server-owned payment summary fields.")
        } catch let error as SupabaseRequestError {
            XCTAssertEqual(error.statusCode, 403)
        }
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

    func insertForumSong(
        songID: String,
        userID: String,
        accessToken: String,
        title: String,
        artist: String
    ) async throws {
        _ = try await requestArray(
            path: "rest/v1/forum_songs",
            method: "POST",
            accessToken: accessToken,
            prefer: "return=representation",
            body: [
                "id": songID,
                "song_title": title,
                "artist_name": artist,
                "normalized_song_title": title.lowercased(),
                "normalized_artist_name": artist.lowercased(),
                "created_by": userID
            ]
        )
    }

    func insertForumPost(
        postID: String,
        songID: String,
        userID: String,
        accessToken: String,
        chartTitle: String,
        storagePath: String
    ) async throws {
        _ = try await requestArray(
            path: "rest/v1/forum_chart_posts",
            method: "POST",
            accessToken: accessToken,
            prefer: "return=representation",
            body: [
                "id": postID,
                "song_id": songID,
                "owner_id": userID,
                "chart_title": chartTitle,
                "arranger_credit": "iChart Integration",
                "creator_display_name": "iChart Integration",
                "tags": ["integration", "forum"],
                "version_note": "Automated integration smoke",
                "layout_style": "simpleChordSheet",
                "pdf_storage_path": storagePath
            ]
        )
    }

    func approveForumPost(postID: String, adminKey: String) async throws {
        let now = ISO8601DateFormatter.smartChartIntegration.string(from: Date())
        _ = try await requestArray(
            path: "rest/v1/forum_chart_posts",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(postID)")],
            accessToken: adminKey,
            prefer: "return=representation",
            body: [
                "status": "published",
                "pdf_provenance_status": "validated",
                "pdf_validated_at": now
            ]
        )
    }

    func insertForumVote(
        voteID: String,
        postID: String,
        userID: String,
        accessToken: String,
        value: Int
    ) async throws {
        _ = try await requestArray(
            path: "rest/v1/forum_votes",
            method: "POST",
            accessToken: accessToken,
            prefer: "return=representation",
            body: [
                "id": voteID,
                "post_id": postID,
                "owner_id": userID,
                "vote_value": value
            ]
        )
    }

    func insertForumComment(
        commentID: String,
        postID: String,
        userID: String,
        accessToken: String,
        body: String
    ) async throws {
        _ = try await requestArray(
            path: "rest/v1/forum_comments",
            method: "POST",
            accessToken: accessToken,
            prefer: "return=representation",
            body: [
                "id": commentID,
                "post_id": postID,
                "owner_id": userID,
                "body": body
            ]
        )
    }

    func insertForumPostReport(
        reportID: String,
        postID: String,
        userID: String,
        accessToken: String
    ) async throws {
        _ = try await requestArray(
            path: "rest/v1/forum_reports",
            method: "POST",
            accessToken: accessToken,
            prefer: "return=representation",
            body: [
                "id": reportID,
                "owner_id": userID,
                "target_type": "post",
                "post_id": postID,
                "reason": "other",
                "detail": "Automated integration smoke"
            ]
        )
    }

    func uploadForumPDF(path: String, accessToken: String, data: Data) async throws {
        _ = try await storageObjectData(
            method: "POST",
            path: path,
            accessToken: accessToken,
            contentType: "application/pdf",
            body: data
        )
    }

    func downloadForumPDF(path: String, accessToken: String) async throws -> Data {
        try await storageObjectData(
            method: "GET",
            path: path,
            accessToken: accessToken,
            authenticatedRead: true,
            contentType: nil,
            body: nil
        )
    }

    func deleteForumPDF(path: String, adminKey: String) async throws {
        _ = try await storageObjectData(
            method: "DELETE",
            path: path,
            accessToken: adminKey,
            contentType: nil,
            body: nil
        )
    }

    func cleanupForumIntegrationUser(
        userID: String?,
        storagePath: String?,
        adminKey: String
    ) async {
        if let storagePath {
            try? await deleteForumPDF(path: storagePath, adminKey: adminKey)
        }

        if let userID {
            try? await deleteAuthUser(userID: userID, adminKey: adminKey)
        }
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
        request.setValue(apiKey(for: accessToken), forHTTPHeaderField: "apikey")
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
            throw SupabaseRequestError(
                method: method,
                path: path,
                statusCode: statusCode,
                message: message
            )
        }

        return data
    }

    private func storageObjectData(
        method: String,
        path: String,
        accessToken: String,
        authenticatedRead: Bool = false,
        contentType: String?,
        body: Data?
    ) async throws -> Data {
        let pathPrefix = authenticatedRead
            ? "storage/v1/object/authenticated/forum_chart_pdfs"
            : "storage/v1/object/forum_chart_pdfs"
        let baseURL = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = try XCTUnwrap(URL(string: "\(baseURL)/\(pathPrefix)/\(path)"))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey(for: accessToken), forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "<empty response>"
            throw SupabaseRequestError(
                method: method,
                path: pathPrefix,
                statusCode: statusCode,
                message: message
            )
        }

        return data
    }

    private func apiKey(for accessToken: String?) -> String {
        if let adminKey = configuration.adminKey,
           accessToken == adminKey {
            return adminKey
        }

        return configuration.publishableKey
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

private struct SupabaseRequestError: LocalizedError {
    let method: String
    let path: String
    let statusCode: Int
    let message: String

    var isEmailSendRateLimit: Bool {
        statusCode == 429 && message.contains("over_email_send_rate_limit")
    }

    var errorDescription: String? {
        "Supabase request \(method) \(path) failed with \(statusCode): \(message)"
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
