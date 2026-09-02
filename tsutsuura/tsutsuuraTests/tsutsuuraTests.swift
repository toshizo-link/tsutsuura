import Foundation
import CryptoKit
import XCTest
@testable import tsutsuura

final class APIClientTests: XCTestCase {
    func testManagedFamilyLeaveClearsStoredBearerButRegularLeavePreservesIt() async throws {
        let configuration = try APIConfiguration(
            baseURL: try XCTUnwrap(URL(string: "https://api.example.com"))
        )
        let managedStore = InMemoryTokenStore(token: "managed-token")
        let managedClient = DefaultAppAPI(
            configuration: configuration,
            transport: ScriptedHTTPTransport(steps: [
                .response(
                    statusCode: 200,
                    data: familyPayloadForLeave(id: "managed-family")
                ),
                .response(
                    statusCode: 200,
                    data: Data(#"{"data":{"accountDeleted":true}}"#.utf8)
                ),
            ]),
            tokenStore: managedStore
        )

        let managedResult = try await managedClient.leaveFamily()

        XCTAssertTrue(managedResult.accountDeleted)
        let managedHasSession = try await managedClient.hasStoredSession()
        XCTAssertFalse(managedHasSession)

        let regularStore = InMemoryTokenStore(token: "regular-token")
        let regularClient = DefaultAppAPI(
            configuration: configuration,
            transport: ScriptedHTTPTransport(steps: [
                .response(
                    statusCode: 200,
                    data: familyPayloadForLeave(id: "regular-family")
                ),
                .response(
                    statusCode: 200,
                    data: Data(#"{"data":{"accountDeleted":false}}"#.utf8)
                ),
            ]),
            tokenStore: regularStore
        )

        let regularResult = try await regularClient.leaveFamily()

        XCTAssertFalse(regularResult.accountDeleted)
        let regularHasSession = try await regularClient.hasStoredSession()
        XCTAssertTrue(regularHasSession)
    }

    func testRequestOTPUsesExpectedPathAndJSONBody() async throws {
        let payload = Data(
            #"{"data":{"requestId":"otp-123","expiresIn":300}}"#.utf8
        )
        let transport = RecordingHTTPTransport(
            statusCode: 200,
            responseData: payload
        )
        let configuration = try APIConfiguration(
            baseURL: try XCTUnwrap(URL(string: "https://api.example.com"))
        )
        let client = DefaultAppAPI(
            configuration: configuration,
            transport: transport,
            tokenStore: InMemoryTokenStore()
        )

        let challenge = try await client.requestOTP(phoneNumber: "090-1234-5678")
        let recordedRequest = await transport.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: String]
        )

        XCTAssertEqual(challenge.requestID, "otp-123")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.example.com/v1/auth/phone/request"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(body, ["phone": "+819012345678"])
    }

    func testDirectInputValidationMatchesServerContractsWithoutNetwork() async throws {
        let transport = ScriptedHTTPTransport(steps: [])
        let client = DefaultAppAPI(
            configuration: try APIConfiguration(
                baseURL: try XCTUnwrap(URL(string: "https://api.example.com"))
            ),
            transport: transport,
            tokenStore: InMemoryTokenStore(token: "token")
        )

        do {
            _ = try await client.requestOTP(phoneNumber: "12345678")
            XCTFail("A phone number without a valid international or domestic prefix must fail")
        } catch {
            XCTAssertEqual(
                error as? TextInputValidationError,
                .invalidPhoneNumber
            )
        }
        do {
            _ = try await client.requestPhoneEnrollment(phoneNumber: "++12345678")
            XCTFail("A malformed enrollment number must fail")
        } catch {
            XCTAssertEqual(
                error as? TextInputValidationError,
                .invalidPhoneNumber
            )
        }
        do {
            _ = try await client.recoverAccount(code: "too-short")
            XCTFail("A malformed recovery code must fail")
        } catch {
            XCTAssertEqual(
                error as? TextInputValidationError,
                .invalidRecoveryCode
            )
        }
        do {
            _ = try await client.createComment(answerID: "answer", body: " \0 ")
            XCTFail("An empty normalized comment must fail")
        } catch {
            XCTAssertEqual(error as? TextInputValidationError, .emptyComment)
        }
        do {
            _ = try await client.updateComment(
                commentID: "comment",
                body: String(repeating: "e\u{301}", count: 501)
            )
            XCTFail("An overlong comment must fail")
        } catch {
            XCTAssertEqual(
                error as? TextInputValidationError,
                .commentTooLong(maximum: Comment.maximumBodyCharacterCount)
            )
        }
        do {
            _ = try await client.reportComment(
                commentID: "comment",
                reason: CommentReportReason.other,
                details: String(repeating: "e\u{301}", count: 251)
            )
            XCTFail("Overlong report details must fail")
        } catch {
            XCTAssertEqual(
                error as? TextInputValidationError,
                .reportDetailsTooLong(
                    maximum: CommentReport.maximumDetailsCharacterCount
                )
            )
        }

        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testDirectResponseFallsBackAfterEnvelopeDecode() async throws {
        let payload = Data(
            #"{"requestId":"otp-direct","expiresIn":120}"#.utf8
        )
        let transport = RecordingHTTPTransport(
            statusCode: 200,
            responseData: payload
        )
        let client = DefaultAppAPI(
            configuration: try APIConfiguration(
                baseURL: try XCTUnwrap(URL(string: "https://api.example.com"))
            ),
            transport: transport,
            tokenStore: InMemoryTokenStore()
        )

        let challenge = try await client.requestOTP(phoneNumber: "+819012345678")

        XCTAssertEqual(challenge.requestID, "otp-direct")
        XCTAssertEqual(challenge.expiresIn, 120)
    }

    func testAuthenticatedRequestUsesBearerToken() async throws {
        let payload = Data(
            """
            {"data":{
              "id":"user-1",
              "displayName":"かえで",
              "avatarURL":null,
              "phoneNumber":"+819012345678",
              "family":null
            }}
            """.utf8
        )
        let transport = RecordingHTTPTransport(
            statusCode: 200,
            responseData: payload
        )
        let configuration = try APIConfiguration(
            baseURL: try XCTUnwrap(URL(string: "https://api.example.com/root"))
        )
        let client = DefaultAppAPI(
            configuration: configuration,
            transport: transport,
            tokenStore: InMemoryTokenStore(token: "secret-token")
        )

        _ = try await client.fetchMe()
        let recordedRequest = await transport.lastRequest
        let request = try XCTUnwrap(recordedRequest)

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.example.com/root/v1/me"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer secret-token"
        )
    }

    func testHomeResponseMapsBackendFeedShape() async throws {
        let payload = Data(
            """
            {"data":{
              "family":{
                "id":"1",
                "name":"わたしの家族",
                "inviteCode":"ABC123",
                "members":[{
                  "id":"1",
                  "displayName":"かえで",
                  "avatarUrl":null,
                  "hasPhone":true,
                  "createdAt":"2026-07-28T01:00:00Z"
                }]
              },
              "todayQuestion":{
                "id":"7",
                "prompt":"今日うれしかったことは？",
                "date":"2026-07-28"
              },
              "myAnswer":{
                "id":"10",
                "answerDate":"2026-07-28",
                "body":"家族と話せたこと",
                "question":{
                  "id":"7",
                  "prompt":"今日うれしかったことは？",
                  "date":"2026-07-28"
                },
                "author":{
                  "id":"1",
                  "displayName":"かえで",
                  "avatarUrl":null
                },
                "likesCount":2,
                "isLiked":true,
                "commentsCount":1,
                "createdAt":"2026-07-28T01:00:00.123Z",
                "updatedAt":"2026-07-28T01:00:00Z"
              },
              "feed":[],
              "nextCursor":null
            }}
            """.utf8
        )
        let transport = RecordingHTTPTransport(
            statusCode: 200,
            responseData: payload
        )
        let client = DefaultAppAPI(
            configuration: try APIConfiguration(
                baseURL: try XCTUnwrap(URL(string: "https://api.example.com"))
            ),
            transport: transport,
            tokenStore: InMemoryTokenStore(token: "token")
        )

        let home = try await client.fetchHome(cursor: nil)

        XCTAssertEqual(home.family?.memberCount, 1)
        XCTAssertEqual(home.todayQuestion?.answer?.id, "10")
        XCTAssertEqual(home.myAnswer?.questionID, "7")
        XCTAssertEqual(home.myAnswer?.likeCount, 2)
        XCTAssertTrue(home.myAnswer?.isLikedByMe == true)
    }

    func testTextOnlyAnswerKeepsJSONRequestCompatibility() async throws {
        let transport = RecordingHTTPTransport(
            statusCode: 200,
            responseData: submittedAnswerPayload()
        )
        let client = DefaultAppAPI(
            configuration: try APIConfiguration(
                baseURL: try XCTUnwrap(URL(string: "https://api.example.com"))
            ),
            transport: transport,
            tokenStore: InMemoryTokenStore(token: "token")
        )

        _ = try await client.submitAnswer(
            questionID: "7",
            body: "テキストだけの回答"
        )

        let recordedRequest = await transport.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json; charset=utf-8"
        )
        let bodyData = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: String]
        )
        XCTAssertEqual(json, ["body": "テキストだけの回答"])
    }

    func testAnswerWithAudioAndPhotosUsesMultipartContract() async throws {
        let transport = RecordingHTTPTransport(
            statusCode: 200,
            responseData: submittedAnswerPayload(includeMedia: true)
        )
        let client = DefaultAppAPI(
            configuration: try APIConfiguration(
                baseURL: try XCTUnwrap(URL(string: "https://api.example.com"))
            ),
            transport: transport,
            tokenStore: InMemoryTokenStore(token: "token")
        )
        let audio = AnswerMediaUpload(
            data: Data("audio-byte-marker".utf8),
            fileName: "recording.m4a",
            mimeType: "audio/mp4",
            durationMilliseconds: 1_234
        )
        let photoOne = AnswerMediaUpload(
            data: Data("photo-one-marker".utf8),
            fileName: "one.jpg",
            mimeType: "image/jpeg"
        )
        let photoTwo = AnswerMediaUpload(
            data: Data("photo-two-marker".utf8),
            fileName: "two.png",
            mimeType: "image/png"
        )

        let answer = try await client.submitAnswer(
            questionID: "7",
            submission: AnswerSubmission(
                body: "音声と写真の回答",
                voiceRecording: audio,
                photos: [photoOne, photoTwo]
            )
        )

        let recordedRequest = await transport.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        let contentType = try XCTUnwrap(
            request.value(forHTTPHeaderField: "Content-Type")
        )
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer token"
        )
        let encodedBody = String(
            decoding: try XCTUnwrap(request.httpBody),
            as: UTF8.self
        )
        XCTAssertTrue(encodedBody.contains("name=\"body\""))
        XCTAssertTrue(encodedBody.contains("音声と写真の回答"))
        XCTAssertTrue(encodedBody.contains("name=\"audio\"; filename=\"recording.m4a\""))
        XCTAssertTrue(encodedBody.contains("name=\"audioDurationMilliseconds\""))
        XCTAssertTrue(encodedBody.contains("1234"))
        XCTAssertEqual(
            encodedBody.components(
                separatedBy: "name=\"photos[]\""
            ).count - 1,
            2
        )
        XCTAssertTrue(encodedBody.contains("audio-byte-marker"))
        XCTAssertTrue(encodedBody.contains("photo-one-marker"))
        XCTAssertTrue(encodedBody.contains("photo-two-marker"))
        XCTAssertEqual(answer.media.map(\.kind), [.audio, .photo])
        XCTAssertEqual(answer.media.first?.durationMilliseconds, 1_234)
    }

    func testAnswerDraftEnforcesPhotoLimitWithoutPartiallyMutating() throws {
        var draft = AnswerDraft()
        let photos = (0...AnswerDraft.maximumPhotoCount).map { index in
            AnswerMediaUpload(
                data: Data([UInt8(index)]),
                fileName: "photo-\(index).jpg",
                mimeType: "image/jpeg"
            )
        }

        XCTAssertThrowsError(try draft.addPhotos(photos)) { error in
            XCTAssertEqual(
                error as? AnswerMediaValidationError,
                .tooManyPhotos(maximum: AnswerDraft.maximumPhotoCount)
            )
        }
        XCTAssertTrue(draft.photos.isEmpty)

        XCTAssertThrowsError(
            try draft.addPhotos([
                AnswerMediaUpload(
                    data: Data(),
                    fileName: "empty.jpg",
                    mimeType: "image/jpeg"
                )
            ])
        ) { error in
            XCTAssertEqual(error as? AnswerMediaValidationError, .emptyPhoto)
        }
        XCTAssertTrue(draft.photos.isEmpty)

        XCTAssertThrowsError(
            try draft.setVoiceRecording(
                AnswerMediaUpload(
                    data: Data(),
                    fileName: "empty.m4a",
                    mimeType: "audio/mp4",
                    durationMilliseconds: 1
                )
            )
        ) { error in
            XCTAssertEqual(error as? AnswerMediaValidationError, .emptyAudio)
        }
        XCTAssertNil(draft.voiceRecording)

        for invalidDuration in [
            0,
            AnswerDraft.maximumAudioDurationMilliseconds + 1,
        ] {
            XCTAssertThrowsError(
                try draft.setVoiceRecording(
                    AnswerMediaUpload(
                        data: Data([0x01]),
                        fileName: "duration.m4a",
                        mimeType: "audio/mp4",
                        durationMilliseconds: invalidDuration
                    )
                )
            ) { error in
                XCTAssertEqual(
                    error as? AnswerMediaValidationError,
                    .invalidAudioDuration(
                        maximumMilliseconds: AnswerDraft
                            .maximumAudioDurationMilliseconds
                    )
                )
            }
        }
        XCTAssertNil(draft.voiceRecording)

        let unsafeFileName = "../\"\u{0001}" + String(
            repeating: "e\u{301}",
            count: 101
        )
        let safeFileName = AnswerMediaUpload.sanitizedFileName(unsafeFileName)
        XCTAssertEqual(
            UnicodeTextValidation.characterCount(safeFileName),
            AnswerMediaUpload.maximumFileNameCharacterCount
        )
        XCTAssertFalse(safeFileName.contains("/"))
        XCTAssertFalse(safeFileName.contains("\""))
        XCTAssertFalse(safeFileName.contains("\u{0001}"))
    }

    func testAnswerDraftAudioTypesMirrorServerAllowlist() throws {
        let supportedTypes = [
            "audio/mp4",
            "audio/x-m4a",
            "audio/aac",
            "audio/x-hx-aac-adts",
            "audio/mpeg",
            "audio/mp3",
            "audio/wav",
            "audio/x-wav",
            "audio/vnd.wave",
            "audio/x-caf",
        ]
        for mimeType in supportedTypes {
            var draft = AnswerDraft()
            XCTAssertNoThrow(
                try draft.setVoiceRecording(
                    AnswerMediaUpload(
                        data: Data([0x01]),
                        fileName: "recording",
                        mimeType: mimeType,
                        durationMilliseconds: 1
                    )
                ),
                "Expected \(mimeType) to match a server-supported audio alias"
            )
            XCTAssertEqual(draft.voiceRecording?.mimeType, mimeType)
        }

        for mimeType in ["audio/ogg", "audio/flac"] {
            var draft = AnswerDraft()
            XCTAssertThrowsError(
                try draft.setVoiceRecording(
                    AnswerMediaUpload(
                        data: Data([0x01]),
                        fileName: "unsupported",
                        mimeType: mimeType,
                        durationMilliseconds: 1
                    )
                )
            ) { error in
                XCTAssertEqual(
                    error as? AnswerMediaValidationError,
                    .invalidAudioType
                )
            }
            XCTAssertNil(draft.voiceRecording)
        }
    }

    func testAnswerMediaDownloadUsesAuthenticationAndResponseMIMEType() async throws {
        let expectedData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let transport = RecordingHTTPTransport(
            statusCode: 200,
            responseData: expectedData,
            responseHeaders: ["Content-Type": "image/jpeg; charset=binary"]
        )
        let client = DefaultAppAPI(
            configuration: try APIConfiguration(
                baseURL: try XCTUnwrap(URL(string: "https://api.example.com"))
            ),
            transport: transport,
            tokenStore: InMemoryTokenStore(token: "media-token")
        )
        let media = AnswerMedia(
            id: "media-photo",
            kind: .photo,
            url: try XCTUnwrap(
                URL(string: "https://api.example.com/v1/media/media-photo")
            ),
            mimeType: "image/png"
        )

        let content = try await client.fetchAnswerMedia(media)

        XCTAssertEqual(content.data, expectedData)
        XCTAssertEqual(content.mimeType, "image/jpeg")
        let recordedRequest = await transport.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer media-token"
        )
    }

    func testConfigurationRequiresHTTPS() throws {
        let insecureURL = try XCTUnwrap(URL(string: "http://api.example.com"))
        XCTAssertThrowsError(
            try APIConfiguration(baseURL: insecureURL)
        )
        XCTAssertThrowsError(
            try APIConfiguration.fromInfoDictionary([:])
        )
    }

    private func submittedAnswerPayload(
        includeMedia: Bool = false
    ) -> Data {
        let media = includeMedia
            ? """
              ,"media":[
                {
                  "id":"media-audio",
                  "kind":"audio",
                  "url":"https://api.example.com/v1/media/media-audio",
                  "mimeType":"audio/mp4",
                  "fileName":"recording.m4a",
                  "byteCount":17,
                  "durationMilliseconds":1234
                },
                {
                  "id":"media-photo",
                  "kind":"photo",
                  "url":"https://api.example.com/v1/media/media-photo",
                  "mimeType":"image/jpeg",
                  "fileName":"one.jpg",
                  "byteCount":16,
                  "durationMilliseconds":null
                }
              ]
              """
            : ""
        return Data(
            """
            {"data":{"answer":{
              "id":"10",
              "answerDate":"2026-07-28",
              "body":"回答",
              "question":{"id":"7","prompt":"質問","date":"2026-07-28"},
              "author":{"id":"1","displayName":"かえで","avatarUrl":null},
              "likesCount":0,
              "isLiked":false,
              "commentsCount":0,
              "createdAt":"2026-07-28T01:00:00Z",
              "updatedAt":"2026-07-28T01:00:00Z"
              \(media)
            }}}
            """.utf8
        )
    }
}

final class PairingLinkParserTests: XCTestCase {
    func testAcceptsOnlySupportedPairingLinkShapesAndTokenBoundaries() throws {
        let minimumToken = String(repeating: "a", count: 40)
        let maximumToken = String(repeating: "Z9_-", count: 32)
        let mixedToken = "AbCdEf0123456789_-" + String(repeating: "x", count: 30)
        let cases: [(String, String)] = [
            ("tsutsuura://pair/\(minimumToken)", minimumToken),
            ("tsutsuura://PAIR?token=\(mixedToken)", mixedToken),
            (
                "https://kttprojects.conohawing.com/tsutsuura-api/api/invite/\(maximumToken)",
                maximumToken
            ),
            (
                "HTTPS://KTTPROJECTS.CONOHAWING.COM/tsutsuura-api/api/invite/\(mixedToken)",
                mixedToken
            ),
        ]

        for (rawURL, expectedToken) in cases {
            let url = try XCTUnwrap(URL(string: rawURL), rawURL)
            XCTAssertEqual(
                PairingLinkParser.token(from: url),
                expectedToken,
                rawURL
            )
        }
    }

    func testRejectsMalformedUntrustedAndNonASCIIPairingLinks() throws {
        let validToken = String(repeating: "a", count: 48)
        let cases = [
            "http://kttprojects.conohawing.com/tsutsuura-api/api/invite/\(validToken)",
            "https://example.com/tsutsuura-api/api/invite/\(validToken)",
            "https://kttprojects.conohawing.com:443/tsutsuura-api/api/invite/\(validToken)",
            "https://user@kttprojects.conohawing.com/tsutsuura-api/api/invite/\(validToken)",
            "https://kttprojects.conohawing.com/TSUTSUURA-API/api/invite/\(validToken)",
            "https://kttprojects.conohawing.com/tsutsuura-api/api/invite/\(validToken)/extra",
            "https://kttprojects.conohawing.com/tsutsuura-api/api/invite",
            "tsutsuura://wrong/\(validToken)",
            "tsutsuura://pair/one/\(validToken)",
            "tsutsuura://pair?token=\(String(repeating: "a", count: 39))",
            "tsutsuura://pair?token=\(String(repeating: "a", count: 129))",
            "tsutsuura://pair?token=\(String(repeating: "a", count: 47)).",
            "tsutsuura://pair?token=\(String(repeating: "家", count: 48))",
            "mailto:family@example.com",
        ]

        for rawURL in cases {
            let url = try XCTUnwrap(URL(string: rawURL), rawURL)
            XCTAssertNil(PairingLinkParser.token(from: url), rawURL)
        }
    }

    func testPairingServerErrorsPreserveActionableRecipientGuidance() {
        let notFound = APIClientError.server(
            statusCode: 404,
            payload: APIErrorPayload(
                code: "pairing_not_found",
                message: "Pairing not found."
            )
        )
        let expired = APIClientError.server(
            statusCode: 410,
            payload: APIErrorPayload(
                code: "pairing_expired",
                message: "Pairing expired."
            )
        )

        XCTAssertEqual(
            notFound.errorDescription,
            "この招待は利用できません。ご家族に新しい設定番号を送ってもらってください。"
        )
        XCTAssertEqual(
            expired.errorDescription,
            "この招待の有効期限が切れています。ご家族に新しい設定番号を送ってもらってください。"
        )
    }
}

final class PhoneNumberValidationTests: XCTestCase {
    func testAcceptsJapaneseAndInternationalE164Lengths() {
        XCTAssertTrue(PhoneNumberValidation.isPlausible("090-1234-5678"))
        XCTAssertTrue(PhoneNumberValidation.isPlausible("+1 212 555 0100"))
        XCTAssertTrue(PhoneNumberValidation.isPlausible("+4412345678"))
        XCTAssertTrue(PhoneNumberValidation.isPlausible("0012125550100"))
        XCTAssertTrue(PhoneNumberValidation.isPlausible("０９０－１２３４－５６７８"))
        XCTAssertEqual(
            PhoneNumberValidation.normalizedForSubmission("＋８１ ９０ １２３４ ５６７８"),
            "+819012345678"
        )
        XCTAssertEqual(
            PhoneNumberValidation.normalizedForSubmission("0012125550100"),
            "+12125550100"
        )
        XCTAssertEqual(
            NumericInputValidation.asciiDigits(in: "１２a３", maximum: 6),
            "123"
        )
    }

    func testRejectsNumbersOutsideE164DigitBounds() {
        XCTAssertFalse(PhoneNumberValidation.isPlausible("1234567"))
        XCTAssertFalse(PhoneNumberValidation.isPlausible("12345678"))
        XCTAssertFalse(PhoneNumberValidation.isPlausible("++12345678"))
        XCTAssertFalse(PhoneNumberValidation.isPlausible("+012345678"))
        XCTAssertFalse(PhoneNumberValidation.isPlausible("0123456789012345"))
        XCTAssertFalse(
            PhoneNumberValidation.isPlausible("+1234567890123456")
        )
        XCTAssertTrue(
            RecoveryCodeValidation.isValid(String(repeating: "A", count: 40))
        )
        XCTAssertFalse(RecoveryCodeValidation.isValid("too-short"))
        XCTAssertFalse(
            RecoveryCodeValidation.isValid(
                String(repeating: "A", count: 39) + "!"
            )
        )
    }
}

final class NameValidationTests: XCTestCase {
    func testUnicodeScalarBoundaryMatchesServerCharacterCounting() {
        let composedAtLimit = String(repeating: "e\u{301}", count: 40)
        let composedOverLimit = composedAtLimit + "e"

        XCTAssertEqual(composedAtLimit.count, 40)
        XCTAssertEqual(NameValidation.characterCount(composedAtLimit), 80)
        XCTAssertTrue(NameValidation.isValid(composedAtLimit))
        XCTAssertEqual(NameValidation.characterCount(composedOverLimit), 81)
        XCTAssertFalse(NameValidation.isValid(composedOverLimit))
        XCTAssertEqual(
            NameValidation.clamped(composedOverLimit),
            composedAtLimit
        )
    }

    func testUnicodeScalarLimitsCoverAnswersCommentsReportsAndHistorySearch() throws {
        let answerAtLimit = String(repeating: "e\u{301}", count: 1_000)
        let answerOverLimit = answerAtLimit + "e"
        XCTAssertEqual(
            UnicodeTextValidation.characterCount(answerAtLimit),
            AnswerDraft.maximumBodyCharacterCount
        )
        XCTAssertNoThrow(try AnswerSubmission(body: answerAtLimit).validate())
        XCTAssertThrowsError(
            try AnswerSubmission(body: answerOverLimit).validate()
        ) { error in
            XCTAssertEqual(
                error as? AnswerMediaValidationError,
                .answerTooLong(maximum: AnswerDraft.maximumBodyCharacterCount)
            )
        }

        let commentOverLimit = String(repeating: "e\u{301}", count: 501)
        let clampedComment = UnicodeTextValidation.clamped(
            commentOverLimit,
            maximumLength: Comment.maximumBodyCharacterCount
        )
        XCTAssertEqual(
            UnicodeTextValidation.characterCount(clampedComment),
            Comment.maximumBodyCharacterCount
        )

        let reportOverLimit = String(repeating: "e\u{301}", count: 251)
        XCTAssertEqual(
            UnicodeTextValidation.characterCount(reportOverLimit),
            CommentReport.maximumDetailsCharacterCount + 2
        )

        let historyOverLimit = String(repeating: "e\u{301}", count: 51)
        let historyQuery = HistoryQuery(searchText: historyOverLimit)
        XCTAssertEqual(
            UnicodeTextValidation.characterCount(historyQuery.searchText),
            HistoryQuery.maximumSearchCharacterCount
        )
        XCTAssertEqual(HistoryQuery.normalizedLimit(-1), 1)
        XCTAssertEqual(HistoryQuery.normalizedLimit(500), 50)
    }
}

final class PushInteractionTests: XCTestCase {
    func testPendingPushDestinationPersistsAcrossFailureAndClearsOnlyAfterAcknowledgement() async throws {
        let suiteName = "tsutsuura-tests.pending-push.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "pending-destination"
        let expected = AppPushDestination.comments(
            answerID: "answer-42",
            commentID: "comment-9"
        )

        let firstProcess = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: storageKey
        )
        await firstProcess.save(expected)

        let relaunchedProcess = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: storageKey
        )
        let restoredDestination = await relaunchedProcess.peek()
        XCTAssertEqual(restoredDestination, expected)

        // A failed navigation deliberately does not acknowledge. A later
        // process must receive the same destination for another attempt.
        let retryProcess = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: storageKey
        )
        let retryDestination = await retryProcess.peek()
        XCTAssertEqual(retryDestination, expected)
        await retryProcess.acknowledge(expected)

        let afterConsumption = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: storageKey
        )
        let consumedDestination = await afterConsumption.peek()
        XCTAssertNil(consumedDestination)
    }

    func testAcknowledgingOlderPushDoesNotEraseNewerArrival() async throws {
        let suiteName = "tsutsuura-tests.pending-push-race.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: "pending-destination-race"
        )
        let first = AppPushDestination.familyAnswer(answerID: "answer-1")
        let second = AppPushDestination.comments(
            answerID: "answer-2",
            commentID: "comment-2"
        )

        await store.save(first)
        let observedFirst = await store.peek()
        XCTAssertEqual(observedFirst, first)
        await store.save(second)
        await store.acknowledge(first)

        let observedSecond = await store.peek()
        XCTAssertEqual(observedSecond, second)
    }

    func testPushDestinationParsesOptionalAndTrimmedQuestionIDs() {
        XCTAssertEqual(
            AppPushDestination.parse(["destination": "today_question"]),
            .todayQuestion(questionID: nil)
        )
        XCTAssertEqual(
            AppPushDestination.parse([
                "destination": "today_question",
                "question_id": "  question-42  ",
            ]),
            .todayQuestion(questionID: "question-42")
        )
        let maximumID = String(repeating: "q", count: 128)
        XCTAssertEqual(
            AppPushDestination.parse([
                "destination": "today_question",
                "question_id": maximumID,
            ]),
            .todayQuestion(questionID: maximumID)
        )
        XCTAssertEqual(
            AppPushDestination.parse([
                "destination": "family_answer",
                "answer_id": " 42 ",
            ]),
            .familyAnswer(answerID: "42")
        )
        XCTAssertEqual(
            AppPushDestination.parse([
                "destination": "comments",
                "answer_id": "42",
                "comment_id": " 9 ",
            ]),
            .comments(answerID: "42", commentID: "9")
        )
    }

    func testPushDestinationRejectsMalformedPayloads() {
        let cases: [[AnyHashable: Any]] = [
            [:],
            ["destination": "comments"],
            ["destination": "family_answer"],
            ["destination": "comments", "answer_id": "42", "comment_id": 9],
            ["destination": 1],
            ["destination": "TODAY_QUESTION"],
            ["destination": "today_question", "question_id": "   "],
            [
                "destination": "today_question",
                "question_id": String(repeating: "q", count: 129),
            ],
            ["destination": "today_question", "question_id": 42],
        ]

        for payload in cases {
            XCTAssertNil(AppPushDestination.parse(payload), "\(payload)")
        }
    }

    func testPushTokenEncoderUsesLowercaseTwoDigitHex() {
        XCTAssertEqual(PushTokenEncoder.hexString(from: Data()), "")
        XCTAssertEqual(
            PushTokenEncoder.hexString(
                from: Data([0x00, 0x01, 0x0F, 0x10, 0xAB, 0xFF])
            ),
            "00010f10abff"
        )
    }
}

final class APIClientRetryTests: XCTestCase {
    func testOwnershipTransferRetriesOnlyItsServerIdempotentPOST() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: familyPayload(ownerID: "user-1")),
            .urlError(.networkConnectionLost),
            .response(statusCode: 200, data: emptyPayload),
            .response(statusCode: 200, data: familyPayload(ownerID: "user-2")),
        ])
        let client = try makeClient(transport: transport)

        let family = try await client.transferFamilyOwnership(to: "user-2")
        let methods = await transport.methods

        XCTAssertEqual(
            family.members.first(where: { $0.familyRole == .owner })?.id,
            "user-2"
        )
        XCTAssertEqual(methods, ["GET", "POST", "POST", "GET"])
    }

    func testOwnershipTransferDoesNotMutateWhenPreflightFails() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .urlError(.badURL),
            .response(statusCode: 200, data: emptyPayload),
        ])
        let client = try makeClient(transport: transport)

        do {
            _ = try await client.transferFamilyOwnership(to: "user-2")
            XCTFail("A failed family preflight must prevent ownership mutation")
        } catch {}

        let methods = await transport.methods
        XCTAssertEqual(methods, ["GET"])
    }

    func testRegularLeaveRetriesWithDurableReceiptKey() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: familyPayload(id: "family-old", ownerID: "user-2")
            ),
            .urlError(.networkConnectionLost),
            .response(
                statusCode: 200,
                data: Data(#"{"data":{"accountDeleted":false}}"#.utf8)
            ),
        ])
        let client = try makeClient(transport: transport)

        let result = try await client.leaveFamily()
        let methods = await transport.methods
        let keys = await transport.idempotencyKeys

        XCTAssertFalse(result.accountDeleted)
        XCTAssertEqual(methods, ["GET", "POST", "POST"])
        XCTAssertNil(keys[0])
        XCTAssertNotNil(keys[1])
        XCTAssertEqual(keys[1], keys[2])
    }

    func testManagedLeaveRetriesAgainstReceiptBeforeAuthentication() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: familyPayload(ownerID: "user-2")),
            .urlError(.networkConnectionLost),
            .response(
                statusCode: 200,
                data: Data(#"{"data":{"accountDeleted":true}}"#.utf8)
            ),
        ])
        let client = try makeClient(transport: transport)

        let result = try await client.leaveFamily()
        let methods = await transport.methods
        let hasSession = try await client.hasStoredSession()

        XCTAssertTrue(result.accountDeleted)
        XCTAssertFalse(hasSession)
        XCTAssertEqual(methods, ["GET", "POST", "POST"])
    }

    func testLeaveDoesNotInterpretArbitraryUnauthorizedAsSuccess() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: familyPayload(ownerID: "user-2")),
            .response(
                statusCode: 401,
                data: Data(
                    #"{"error":{"code":"invalid_session","message":"expired"}}"#.utf8
                )
            ),
        ])
        let client = try makeClient(transport: transport)

        do {
            _ = try await client.leaveFamily()
            XCTFail("An unreceipted 401 must remain an authentication failure")
        } catch APIClientError.unauthorized {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let methodsBeforeRestore = await transport.methods
        XCTAssertEqual(methodsBeforeRestore, ["GET", "POST"])
        let hasStoredSession = try await client.hasStoredSession()
        XCTAssertFalse(hasStoredSession)
        let methodsAfterRestore = await transport.methods
        XCTAssertEqual(methodsAfterRestore, ["GET", "POST"])
    }

    func testLeaveDoesNotMutateWhenPreflightFails() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .urlError(.badURL),
            .response(statusCode: 200, data: emptyPayload),
        ])
        let client = try makeClient(transport: transport)

        do {
            _ = try await client.leaveFamily()
            XCTFail("A failed family preflight must prevent leave mutation")
        } catch {}

        let methods = await transport.methods
        XCTAssertEqual(methods, ["GET"])
    }

    func testDeleteAccountRetriesWithDurableReceiptKey() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: userPayload),
            .urlError(.networkConnectionLost),
            .response(
                statusCode: 200,
                data: emptyPayload
            ),
        ])
        let tokenStore = InMemoryTokenStore(token: "token")
        let client = try makeClient(
            transport: transport,
            tokenStore: tokenStore
        )

        try await client.deleteAccount()

        let methods = await transport.methods
        let keys = await transport.idempotencyKeys
        let hasSession = try await client.hasStoredSession()
        XCTAssertEqual(methods, ["GET", "DELETE", "DELETE"])
        XCTAssertNil(keys[0])
        XCTAssertNotNil(keys[1])
        XCTAssertEqual(keys[1], keys[2])
        XCTAssertFalse(hasSession)
    }

    func testDeleteAccountDoesNotInterpretArbitraryUnauthorizedAsSuccess() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: userPayload),
            .response(
                statusCode: 401,
                data: Data(
                    #"{"error":{"code":"invalid_session","message":"expired"}}"#.utf8
                )
            ),
        ])
        let client = try makeClient(transport: transport)

        do {
            try await client.deleteAccount()
            XCTFail("An unreceipted 401 must remain an authentication failure")
        } catch APIClientError.unauthorized {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let methods = await transport.methods
        XCTAssertEqual(methods, ["GET", "DELETE"])
    }

    func testDeleteAccountDoesNotMutateWhenPreflightFails() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .urlError(.badURL),
            .response(statusCode: 200, data: emptyPayload),
        ])
        let tokenStore = InMemoryTokenStore(token: "token")
        let client = try makeClient(
            transport: transport,
            tokenStore: tokenStore
        )

        do {
            try await client.deleteAccount()
            XCTFail("A failed account preflight must prevent deletion")
        } catch {}

        let methods = await transport.methods
        let hasSession = try await client.hasStoredSession()
        XCTAssertEqual(methods, ["GET"])
        XCTAssertTrue(hasSession)
    }

    func testSignOutRetainsBearerWhenRemoteRevocationFails() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 503,
                data: Data(
                    #"{"error":{"code":"unavailable","message":"later"}}"#.utf8
                )
            ),
        ])
        let tokenStore = InMemoryTokenStore(token: "logout-token")
        let client = try makeClient(
            transport: transport,
            tokenStore: tokenStore,
            retryPolicy: .disabled
        )

        do {
            try await client.signOut()
            XCTFail("A failed remote revocation must not report logout success")
        } catch {}

        let retainedToken = try await tokenStore.readToken()
        XCTAssertEqual(retainedToken, "logout-token")
        let methods = await transport.methods
        XCTAssertEqual(methods, ["POST"])
    }

    func testSignOutClearsBearerAfterSuccessOrUnauthorized() async throws {
        let successStore = InMemoryTokenStore(token: "success-token")
        let successClient = try makeClient(
            transport: ScriptedHTTPTransport(steps: [
                .response(statusCode: 200, data: emptyPayload),
            ]),
            tokenStore: successStore,
            retryPolicy: .disabled
        )
        try await successClient.signOut()
        let successToken = try await successStore.readToken()
        XCTAssertNil(successToken)

        let expiredStore = InMemoryTokenStore(token: "expired-token")
        let expiredClient = try makeClient(
            transport: ScriptedHTTPTransport(steps: [
                .response(
                    statusCode: 401,
                    data: Data(
                        #"{"error":{"code":"invalid_session","message":"expired"}}"#.utf8
                    )
                ),
            ]),
            tokenStore: expiredStore,
            retryPolicy: .disabled
        )
        try await expiredClient.signOut()
        let expiredToken = try await expiredStore.readToken()
        XCTAssertNil(expiredToken)
    }

    func testPersistedMutationStateUsesKeyedNamesAndEncryptedValues() async throws {
        let suiteName =
            "tsutsuura.tests.protected-mutation-state.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let protectionKey = Data(repeating: 0xA7, count: 32)
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            mutationProtectionKey: protectionKey
        )

        do {
            _ = try await firstClient.activateFamilyPairing(.code("123456"))
            XCTFail("The first response must be lost")
        } catch {}

        let firstRequestKeys = await firstTransport.idempotencyKeys
        let receipt = try XCTUnwrap(firstRequestKeys.first ?? nil)
        let storedKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("tsutsuura.idempotency.v2.pairing.activate.")
        }
        XCTAssertEqual(storedKeys.count, 1)
        let protectedData = try XCTUnwrap(
            defaults.data(forKey: try XCTUnwrap(storedKeys.first))
        )
        XCTAssertNil(protectedData.range(of: Data(receipt.utf8)))

        let legacyInput = "pairing.activate\u{0}code\u{0}123456"
        let legacyDigest = SHA256.hash(data: Data(legacyInput.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
        XCTAssertNil(
            defaults.object(
                forKey: "tsutsuura.idempotency.v1.pairing.activate."
                    + legacyDigest
            )
        )

        let replayTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: authPayload(token: "protected-replay")
            ),
        ])
        let replayClient = try makeClient(
            transport: replayTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            mutationProtectionKey: protectionKey
        )
        _ = try await replayClient.activateFamilyPairing(.code("123456"))
        let replayKeys = await replayTransport.idempotencyKeys
        XCTAssertEqual(
            replayKeys.first ?? nil,
            receipt
        )
    }

    func testLegacyMutationRecordMigratesToProtectedStorage() async throws {
        let suiteName =
            "tsutsuura.tests.legacy-mutation-migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyInput = "pairing.activate\u{0}code\u{0}654321"
        let legacyDigest = SHA256.hash(data: Data(legacyInput.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
        let legacyStorageKey =
            "tsutsuura.idempotency.v1.pairing.activate." + legacyDigest
        let legacyReceipt = UUID().uuidString.lowercased()
        defaults.set(
            try mutationRecordData(value: legacyReceipt, createdAt: Date()),
            forKey: legacyStorageKey
        )
        let transport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let client = try makeClient(
            transport: transport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            mutationProtectionKey: Data(repeating: 0xB8, count: 32)
        )

        do {
            _ = try await client.activateFamilyPairing(.code("654321"))
            XCTFail("The migrated retry response must be lost")
        } catch {}

        let migratedRequestKeys = await transport.idempotencyKeys
        XCTAssertEqual(
            migratedRequestKeys.first ?? nil,
            legacyReceipt
        )
        XCTAssertNil(defaults.object(forKey: legacyStorageKey))
        let protectedKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("tsutsuura.idempotency.v2.pairing.activate.")
        }
        XCTAssertEqual(protectedKeys.count, 1)
        let protectedData = try XCTUnwrap(
            defaults.data(forKey: try XCTUnwrap(protectedKeys.first))
        )
        XCTAssertNil(protectedData.range(of: Data(legacyReceipt.utf8)))
    }

    func testMutationFailsClosedWhenProtectionKeyIsInvalid() async throws {
        let transport = ScriptedHTTPTransport(steps: [])
        let client = try makeClient(
            transport: transport,
            authenticated: false,
            retryPolicy: .disabled,
            mutationProtectionKey: Data(repeating: 0x01, count: 31)
        )

        do {
            _ = try await client.verifyOTP(
                requestID: String(repeating: "r", count: 32),
                code: "123456"
            )
            XCTFail("A mutation must not proceed without its protection key")
        } catch {
            XCTAssertEqual(
                error as? MutationProtectionKeyError,
                .invalidKeyData
            )
        }
        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testRecoveryRetryReusesExactIdempotencyKeyAndBody() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
            .response(statusCode: 200, data: authPayload(token: "recovered")),
        ])
        let client = try makeClient(
            transport: transport,
            authenticated: false
        )

        let session = try await client.recoverAccount(
            code: String(repeating: "R", count: 40)
        )
        let keys = await transport.idempotencyKeys
        let bodies = await transport.bodies

        XCTAssertEqual(session.accessToken, "recovered")
        let methods = await transport.methods
        XCTAssertEqual(methods, ["POST", "POST"])
        XCTAssertNotNil(keys[0])
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertEqual(bodies[0], bodies[1])
    }

    func testPairingActivationRetryReusesExactIdempotencyKeyAndBody() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
            .response(statusCode: 200, data: authPayload(token: "paired")),
        ])
        let client = try makeClient(
            transport: transport,
            authenticated: false
        )

        let session = try await client.activateFamilyPairing(.code("123456"))
        let keys = await transport.idempotencyKeys
        let bodies = await transport.bodies

        XCTAssertEqual(session.accessToken, "paired")
        let methods = await transport.methods
        XCTAssertEqual(methods, ["POST", "POST"])
        XCTAssertNotNil(keys[0])
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertEqual(bodies[0], bodies[1])
    }

    func testCommentRetryReusesExactIdempotencyKeyAndBody() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
            .response(
                statusCode: 200,
                data: createdCommentPayload(
                    id: "comment-1",
                    answerID: "answer-1",
                    body: "覚えているよ"
                )
            ),
        ])
        let client = try makeClient(transport: transport)

        let comment = try await client.createComment(
            answerID: "answer-1",
            body: "覚えているよ"
        )
        let keys = await transport.idempotencyKeys
        let bodies = await transport.bodies

        XCTAssertEqual(comment.id, "comment-1")
        let methods = await transport.methods
        XCTAssertEqual(methods, ["POST", "POST"])
        XCTAssertNotNil(keys[0])
        XCTAssertEqual(keys[0], keys[1])
        XCTAssertEqual(bodies[0], bodies[1])
    }

    func testCommentMutationKeysAreBoundToTheAuthenticatedAccount() async throws {
        let suiteName = "tsutsuura.tests.comment-actor-binding.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            tokenStore: InMemoryTokenStore(token: "account-a"),
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        do {
            _ = try await firstClient.createComment(
                answerID: "answer-shared",
                body: "同じ本文"
            )
        } catch {}
        do {
            _ = try await firstClient.replyToComment(
                answerID: "answer-shared",
                parentCommentID: "parent-shared",
                body: "同じ返信"
            )
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let secondTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: createdCommentPayload(
                    id: "comment-account-b",
                    answerID: "answer-shared",
                    body: "同じ本文"
                )
            ),
            .response(
                statusCode: 200,
                data: createdCommentPayload(
                    id: "reply-account-b",
                    answerID: "answer-shared",
                    body: "同じ返信"
                )
            ),
        ])
        let secondClient = try makeClient(
            transport: secondTransport,
            tokenStore: InMemoryTokenStore(token: "account-b"),
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        _ = try await secondClient.createComment(
            answerID: "answer-shared",
            body: "同じ本文"
        )
        _ = try await secondClient.replyToComment(
            answerID: "answer-shared",
            parentCommentID: "parent-shared",
            body: "同じ返信"
        )
        let secondKeys = await secondTransport.idempotencyKeys

        XCTAssertNotEqual(secondKeys[0], firstKeys[0])
        XCTAssertNotEqual(secondKeys[1], firstKeys[1])
    }

    func testAccountDeleteReceiptReconcilesAfterRelaunchWithoutBearer() async throws {
        let suiteName = "tsutsuura.tests.account-delete.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: userPayload),
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            tokenStore: InMemoryTokenStore(token: "deleted-bearer"),
            retryPolicy: .disabled,
            idempotencyDefaults: firstDefaults
        )

        do {
            try await firstClient.deleteAccount()
            XCTFail("The first process must lose the committed response")
        } catch {}

        let firstKeys = await firstTransport.idempotencyKeys
        XCTAssertNotNil(firstKeys[1])

        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let secondTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: emptyPayload),
        ])
        let relaunchedClient = try makeClient(
            transport: secondTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: secondDefaults
        )

        let hasStoredSession = try await relaunchedClient.hasStoredSession()
        XCTAssertFalse(hasStoredSession)
        let secondKeys = await secondTransport.idempotencyKeys
        let secondAuthorization = await secondTransport.authorizationHeaders
        let secondMethods = await secondTransport.methods
        XCTAssertEqual(secondMethods, ["DELETE"])
        XCTAssertEqual(secondKeys[0], firstKeys[1])
        XCTAssertNil(secondAuthorization[0])
    }

    func testManagedLeaveReceiptReconcilesAfterRelaunchWithoutBearer() async throws {
        let suiteName = "tsutsuura.tests.managed-leave.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: familyPayload(ownerID: "user-2")),
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            tokenStore: InMemoryTokenStore(token: "managed-bearer"),
            retryPolicy: .disabled,
            idempotencyDefaults: firstDefaults
        )

        do {
            _ = try await firstClient.leaveFamily()
            XCTFail("The first process must lose the committed response")
        } catch {}

        let firstKeys = await firstTransport.idempotencyKeys
        XCTAssertNotNil(firstKeys[1])

        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let secondTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: Data(#"{"data":{"accountDeleted":true}}"#.utf8)
            ),
        ])
        let relaunchedClient = try makeClient(
            transport: secondTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: secondDefaults
        )

        let hasStoredSession = try await relaunchedClient.hasStoredSession()
        XCTAssertFalse(hasStoredSession)
        let secondKeys = await secondTransport.idempotencyKeys
        let secondAuthorization = await secondTransport.authorizationHeaders
        let secondMethods = await secondTransport.methods
        XCTAssertEqual(secondMethods, ["POST"])
        XCTAssertEqual(secondKeys[0], firstKeys[1])
        XCTAssertNil(secondAuthorization[0])
    }

    func testManualLeaveRetryUsesPendingReceiptBeforeFamilyPreflight() async throws {
        let suiteName = "tsutsuura.tests.manual-leave.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: familyPayload(id: "old-family", ownerID: "user-2")
            ),
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            tokenStore: InMemoryTokenStore(token: "same-bearer"),
            retryPolicy: .disabled,
            idempotencyDefaults: firstDefaults
        )
        do {
            _ = try await firstClient.leaveFamily()
            XCTFail("The first response must be lost")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let retryTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: Data(#"{"data":{"accountDeleted":false}}"#.utf8)
            ),
        ])
        let retryClient = try makeClient(
            transport: retryTransport,
            tokenStore: InMemoryTokenStore(token: "same-bearer"),
            retryPolicy: .disabled,
            idempotencyDefaults: try XCTUnwrap(
                UserDefaults(suiteName: suiteName)
            )
        )

        let result = try await retryClient.leaveFamily()
        let retryMethods = await retryTransport.methods
        let retryKeys = await retryTransport.idempotencyKeys
        XCTAssertFalse(result.accountDeleted)
        XCTAssertEqual(retryMethods, ["POST"])
        XCTAssertEqual(retryKeys[0], firstKeys[1])
    }

    func testManualAccountDeleteRetryUsesPendingReceiptBeforeProfilePreflight() async throws {
        let suiteName = "tsutsuura.tests.manual-delete.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: userPayload),
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            tokenStore: InMemoryTokenStore(token: "same-bearer"),
            retryPolicy: .disabled,
            idempotencyDefaults: firstDefaults
        )
        do {
            try await firstClient.deleteAccount()
            XCTFail("The first response must be lost")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let retryTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: emptyPayload),
        ])
        let retryClient = try makeClient(
            transport: retryTransport,
            tokenStore: InMemoryTokenStore(token: "same-bearer"),
            retryPolicy: .disabled,
            idempotencyDefaults: try XCTUnwrap(
                UserDefaults(suiteName: suiteName)
            )
        )

        try await retryClient.deleteAccount()
        let retryMethods = await retryTransport.methods
        let retryKeys = await retryTransport.idempotencyKeys
        XCTAssertEqual(retryMethods, ["DELETE"])
        XCTAssertEqual(retryKeys[0], firstKeys[1])
    }

    func testPairingReentryPreviewAndActivationReusePersistedKey() async throws {
        let suiteName = "tsutsuura.tests.pairing-reentry.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: firstDefaults
        )
        do {
            _ = try await firstClient.activateFamilyPairing(.code("123456"))
            XCTFail("The first activation response must be lost")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let reentryTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: pairingPreviewPayload),
            .response(statusCode: 200, data: authPayload(token: "paired-replay")),
        ])
        let reentryClient = try makeClient(
            transport: reentryTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: try XCTUnwrap(
                UserDefaults(suiteName: suiteName)
            )
        )

        let preview = try await reentryClient.previewFamilyPairing(.code("123456"))
        let session = try await reentryClient.activateFamilyPairing(.code("123456"))
        let reentryKeys = await reentryTransport.idempotencyKeys
        XCTAssertEqual(preview.member.displayName, "おばあちゃん")
        XCTAssertEqual(session.accessToken, "paired-replay")
        XCTAssertEqual(reentryKeys, [firstKeys[0], firstKeys[0]])
    }

    func testPairingReentryReusesCodeActivationKeyWithTokenRepresentation() async throws {
        let suiteName = "tsutsuura.tests.pairing-code-token.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        do {
            _ = try await firstClient.activateFamilyPairing(.code("123456"))
            XCTFail("The first activation response must be lost")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let reentryTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: pairingPreviewPayload),
            .response(statusCode: 200, data: authPayload(token: "token-replay")),
        ])
        let reentryClient = try makeClient(
            transport: reentryTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        let tokenCredential = FamilyPairingCredential.token("invite-token")

        _ = try await reentryClient.previewFamilyPairing(tokenCredential)
        _ = try await reentryClient.activateFamilyPairing(tokenCredential)
        let reentryKeys = await reentryTransport.idempotencyKeys
        let reentryBodies = await reentryTransport.bodies

        XCTAssertEqual(reentryKeys, [firstKeys[0], firstKeys[0]])
        XCTAssertTrue(reentryBodies.allSatisfy {
            guard let body = $0,
                  let object = try? JSONSerialization.jsonObject(with: body)
                    as? [String: Any] else {
                return false
            }
            return object["token"] as? String == "invite-token"
                && object["code"] == nil
        })
    }

    func testPairingReentryReusesTokenActivationKeyWithCodeRepresentation() async throws {
        let suiteName = "tsutsuura.tests.pairing-token-code.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        do {
            _ = try await firstClient.activateFamilyPairing(
                .token("invite-token")
            )
            XCTFail("The first activation response must be lost")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let reentryTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: pairingPreviewPayload),
            .response(statusCode: 200, data: authPayload(token: "code-replay")),
        ])
        let reentryClient = try makeClient(
            transport: reentryTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        let codeCredential = FamilyPairingCredential.code("123456")

        _ = try await reentryClient.previewFamilyPairing(codeCredential)
        _ = try await reentryClient.activateFamilyPairing(codeCredential)
        let reentryKeys = await reentryTransport.idempotencyKeys
        let reentryBodies = await reentryTransport.bodies

        XCTAssertEqual(reentryKeys, [firstKeys[0], firstKeys[0]])
        XCTAssertTrue(reentryBodies.allSatisfy {
            guard let body = $0,
                  let object = try? JSONSerialization.jsonObject(with: body)
                    as? [String: Any] else {
                return false
            }
            return object["code"] as? String == "123456"
                && object["token"] == nil
        })
    }

    func testDifferentPendingInviteDoesNotConsumeLostActivationKey() async throws {
        let suiteName = "tsutsuura.tests.pairing-distinct-pending.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        do {
            _ = try await firstClient.activateFamilyPairing(.code("111111"))
            XCTFail("The first activation response must be lost")
        } catch {}
        let originalKeys = await firstTransport.idempotencyKeys

        let secondTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: pendingPairingPreviewPayload),
            .response(statusCode: 200, data: authPayload(token: "new-invite")),
            .response(statusCode: 200, data: pairingPreviewPayload),
        ])
        let secondClient = try makeClient(
            transport: secondTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )

        _ = try await secondClient.previewFamilyPairing(.code("222222"))
        _ = try await secondClient.activateFamilyPairing(.code("222222"))
        _ = try await secondClient.previewFamilyPairing(.code("111111"))
        let secondKeys = await secondTransport.idempotencyKeys

        XCTAssertEqual(secondKeys[0], originalKeys[0])
        XCTAssertNotEqual(secondKeys[1], originalKeys[0])
        XCTAssertEqual(secondKeys[2], originalKeys[0])
    }

    func testExpiredAbandonedPairingKeyDoesNotBlockAlternateCredentialRecovery() async throws {
        let suiteName = "tsutsuura.tests.pairing-stale-key.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let later = startedAt.addingTimeInterval(30 * 24 * 60 * 60 + 1)

        let abandonedTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let abandonedClient = try makeClient(
            transport: abandonedTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            now: { startedAt }
        )
        do {
            _ = try await abandonedClient.activateFamilyPairing(.code("111111"))
        } catch {}

        let currentTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let currentClient = try makeClient(
            transport: currentTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            now: { later }
        )
        do {
            _ = try await currentClient.activateFamilyPairing(.code("222222"))
        } catch {}
        let currentKeys = await currentTransport.idempotencyKeys

        let replayTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: pairingPreviewPayload),
            .response(statusCode: 200, data: authPayload(token: "fresh-pairing")),
        ])
        let replayClient = try makeClient(
            transport: replayTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            now: { later }
        )
        let tokenCredential = FamilyPairingCredential.token("current-token")
        _ = try await replayClient.previewFamilyPairing(tokenCredential)
        let session = try await replayClient.activateFamilyPairing(tokenCredential)
        let replayKeys = await replayTransport.idempotencyKeys

        XCTAssertEqual(session.accessToken, "fresh-pairing")
        XCTAssertEqual(replayKeys, [currentKeys[0], currentKeys[0]])
    }

    func testRecoveryReentryReusesPersistedKeyAcrossClientRecreation() async throws {
        let suiteName = "tsutsuura.tests.recovery-reentry.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: firstDefaults
        )
        do {
            _ = try await firstClient.recoverAccount(
                code: String(repeating: "R", count: 40)
            )
            XCTFail("The first recovery response must be lost")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let reentryTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: authPayload(token: "recovery-replay")),
        ])
        let reentryClient = try makeClient(
            transport: reentryTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: try XCTUnwrap(
                UserDefaults(suiteName: suiteName)
            )
        )

        _ = try await reentryClient.recoverAccount(
            code: String(repeating: "R", count: 40)
        )
        let reentryKeys = await reentryTransport.idempotencyKeys
        XCTAssertEqual(reentryKeys[0], firstKeys[0])
    }

    func testCommentReentryAndRateLimitKeepPersistedKey() async throws {
        let suiteName = "tsutsuura.tests.comment-reentry.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 429,
                data: Data(
                    #"{"error":{"code":"rate_limited","message":"later"}}"#.utf8
                )
            ),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            retryPolicy: .disabled,
            idempotencyDefaults: firstDefaults
        )
        do {
            _ = try await firstClient.createComment(
                answerID: "answer-1",
                body: "再試行するコメント"
            )
            XCTFail("The throttled response must fail")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let reentryTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: createdCommentPayload(
                    id: "comment-replay",
                    answerID: "answer-1",
                    body: "再試行するコメント"
                )
            ),
        ])
        let reentryClient = try makeClient(
            transport: reentryTransport,
            retryPolicy: .disabled,
            idempotencyDefaults: try XCTUnwrap(
                UserDefaults(suiteName: suiteName)
            )
        )

        let comment = try await reentryClient.createComment(
            answerID: "answer-1",
            body: "再試行するコメント"
        )
        let reentryKeys = await reentryTransport.idempotencyKeys
        XCTAssertEqual(comment.id, "comment-replay")
        XCTAssertEqual(reentryKeys[0], firstKeys[0])
    }

    func testCommentReentryStartsANewReceiptAfterThirtyDayPrivacyWindow() async throws {
        let suiteName = "tsutsuura.tests.comment-retention.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let firstTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 429,
                data: Data(
                    #"{"error":{"code":"rate_limited","message":"later"}}"#.utf8
                )
            ),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            now: { startedAt }
        )
        do {
            _ = try await firstClient.createComment(
                answerID: "answer-privacy-window",
                body: "期限付きのコメント"
            )
            XCTFail("The throttled response must fail")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let laterTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: createdCommentPayload(
                    id: "comment-new-window",
                    answerID: "answer-privacy-window",
                    body: "期限付きのコメント"
                )
            ),
        ])
        let laterClient = try makeClient(
            transport: laterTransport,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            now: {
                startedAt.addingTimeInterval(30 * 24 * 60 * 60 + 1)
            }
        )
        _ = try await laterClient.createComment(
            answerID: "answer-privacy-window",
            body: "期限付きのコメント"
        )
        let laterKeys = await laterTransport.idempotencyKeys

        XCTAssertNotEqual(laterKeys[0], firstKeys[0])
    }

    func testOrganizerBootstrapReentryReusesPersistedKey() async throws {
        let suiteName = "tsutsuura.tests.organizer-reentry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        do {
            _ = try await firstClient.createOrganizerFamily(
                organizerName: "ゆうた",
                familyName: "田中家"
            )
            XCTFail("The first organizer response must be lost")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let replayTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: authPayload(token: "organizer-replay")),
        ])
        let replayClient = try makeClient(
            transport: replayTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        let session = try await replayClient.createOrganizerFamily(
            organizerName: "ゆうた",
            familyName: "田中家"
        )
        let replayKeys = await replayTransport.idempotencyKeys

        XCTAssertEqual(session.accessToken, "organizer-replay")
        XCTAssertEqual(replayKeys[0], firstKeys[0])
    }

    func testManagedMemberReentryReusesPersistedActorBoundKey() async throws {
        let suiteName = "tsutsuura.tests.managed-member-reentry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            tokenStore: InMemoryTokenStore(token: "same-actor-token"),
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        do {
            _ = try await firstClient.addManagedFamilyMember(
                displayName: "おばあちゃん"
            )
            XCTFail("The first managed-member response must be lost")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let replayTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: managedMemberPayload),
        ])
        let replayClient = try makeClient(
            transport: replayTransport,
            tokenStore: InMemoryTokenStore(token: "same-actor-token"),
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        let member = try await replayClient.addManagedFamilyMember(
            displayName: "おばあちゃん"
        )
        let replayKeys = await replayTransport.idempotencyKeys

        XCTAssertEqual(member.id, "managed-1")
        XCTAssertEqual(replayKeys[0], firstKeys[0])
    }

    func testSetupMutationsStartNewKeysAfterThirtyDayReceiptWindow() async throws {
        let suiteName = "tsutsuura.tests.setup-retention.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            tokenStore: InMemoryTokenStore(token: "setup-retention-token"),
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            now: { startedAt }
        )
        do {
            _ = try await firstClient.addManagedFamilyMember(
                displayName: "おばあちゃん"
            )
        } catch {}
        do {
            _ = try await firstClient.createOrganizerFamily(
                organizerName: "ゆうた",
                familyName: "田中家"
            )
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let laterTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: managedMemberPayload),
            .response(statusCode: 200, data: authPayload(token: "new-organizer")),
        ])
        let laterClient = try makeClient(
            transport: laterTransport,
            tokenStore: InMemoryTokenStore(token: "setup-retention-token"),
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            now: {
                startedAt.addingTimeInterval(30 * 24 * 60 * 60 + 1)
            }
        )
        _ = try await laterClient.addManagedFamilyMember(
            displayName: "おばあちゃん"
        )
        _ = try await laterClient.createOrganizerFamily(
            organizerName: "ゆうた",
            familyName: "田中家"
        )
        let laterKeys = await laterTransport.idempotencyKeys

        XCTAssertNotEqual(laterKeys[0], firstKeys[0])
        XCTAssertNotEqual(laterKeys[1], firstKeys[1])
    }

    func testOTPVerificationReentryReusesPersistedKeyAndBody() async throws {
        let suiteName = "tsutsuura.tests.otp-verification-reentry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let requestID = String(repeating: "a", count: 32)
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        do {
            _ = try await firstClient.verifyOTP(
                requestID: requestID,
                code: "123456"
            )
            XCTFail("The first OTP response must be lost")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys
        let firstBodies = await firstTransport.bodies

        let replayTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: authPayload(token: "otp-replay")),
        ])
        let replayClient = try makeClient(
            transport: replayTransport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        let session = try await replayClient.verifyOTP(
            requestID: requestID,
            code: "123456"
        )
        let replayKeys = await replayTransport.idempotencyKeys
        let replayBodies = await replayTransport.bodies

        XCTAssertEqual(session.accessToken, "otp-replay")
        XCTAssertEqual(replayKeys[0], firstKeys[0])
        XCTAssertEqual(replayBodies[0], firstBodies[0])
    }

    func testPhoneEnrollmentVerificationReentryReusesActorBoundKeyAndBody() async throws {
        let suiteName = "tsutsuura.tests.enrollment-verification-reentry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let requestID = String(repeating: "b", count: 32)
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            tokenStore: InMemoryTokenStore(token: "enrollment-actor"),
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        do {
            _ = try await firstClient.verifyPhoneEnrollment(
                requestID: requestID,
                code: "654321"
            )
            XCTFail("The first enrollment response must be lost")
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys
        let firstBodies = await firstTransport.bodies

        let replayTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: userPayload),
        ])
        let replayClient = try makeClient(
            transport: replayTransport,
            tokenStore: InMemoryTokenStore(token: "enrollment-actor"),
            retryPolicy: .disabled,
            idempotencyDefaults: defaults
        )
        let user = try await replayClient.verifyPhoneEnrollment(
            requestID: requestID,
            code: "654321"
        )
        let replayKeys = await replayTransport.idempotencyKeys
        let replayBodies = await replayTransport.bodies

        XCTAssertEqual(user.id, "user-1")
        XCTAssertEqual(replayKeys[0], firstKeys[0])
        XCTAssertEqual(replayBodies[0], firstBodies[0])
    }

    func testVerificationMutationsStartNewKeysAfterThirtyDayReceiptWindow() async throws {
        let suiteName = "tsutsuura.tests.verification-retention.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let otpRequestID = String(repeating: "c", count: 32)
        let enrollmentRequestID = String(repeating: "d", count: 32)
        let firstTransport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
            .urlError(.networkConnectionLost),
        ])
        let firstClient = try makeClient(
            transport: firstTransport,
            tokenStore: InMemoryTokenStore(token: "verification-actor"),
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            now: { startedAt }
        )
        do {
            _ = try await firstClient.verifyOTP(
                requestID: otpRequestID,
                code: "111111"
            )
        } catch {}
        do {
            _ = try await firstClient.verifyPhoneEnrollment(
                requestID: enrollmentRequestID,
                code: "222222"
            )
        } catch {}
        let firstKeys = await firstTransport.idempotencyKeys

        let laterTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: authPayload(token: "new-otp-window")),
            .response(statusCode: 200, data: userPayload),
        ])
        let laterClient = try makeClient(
            transport: laterTransport,
            tokenStore: InMemoryTokenStore(token: "verification-actor"),
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            now: {
                startedAt.addingTimeInterval(30 * 24 * 60 * 60 + 1)
            }
        )
        _ = try await laterClient.verifyOTP(
            requestID: otpRequestID,
            code: "111111"
        )
        _ = try await laterClient.verifyPhoneEnrollment(
            requestID: enrollmentRequestID,
            code: "222222"
        )
        let laterKeys = await laterTransport.idempotencyKeys

        XCTAssertNotEqual(laterKeys[0], firstKeys[0])
        XCTAssertNotEqual(laterKeys[1], firstKeys[1])
    }

    func testFirstSecureStateUsePrunesOnlyExpiredBoundedMutationRecords() async throws {
        let suiteName = "tsutsuura.tests.mutation-global-prune.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let currentTime = Date(timeIntervalSince1970: 1_788_192_000)
        let retention: TimeInterval = 30 * 24 * 60 * 60
        let prefix = "tsutsuura.idempotency.v1."
        let boundedOperations = [
            "otp.verify",
            "phone.enrollment.verify",
            "family.create",
            "managed-member.create",
            "account.recovery",
            "pairing.activate",
            "comment.create",
            "comment.reply",
        ]
        var expiredKeys: [String] = []
        var activeRecords: [String: Data] = [:]

        for (index, operation) in boundedOperations.enumerated() {
            let expiredKey = prefix + operation + ".unrelated-expired-\(index)"
            let activeKey = prefix + operation + ".active-\(index)"
            let expiredRecord = try mutationRecordData(
                value: "expired-\(index)",
                createdAt: currentTime.addingTimeInterval(-retention - 1)
            )
            let activeRecord = try mutationRecordData(
                value: "active-\(index)",
                createdAt: currentTime.addingTimeInterval(-retention + 1)
            )
            defaults.set(expiredRecord, forKey: expiredKey)
            defaults.set(activeRecord, forKey: activeKey)
            expiredKeys.append(expiredKey)
            activeRecords[activeKey] = activeRecord
        }

        let lifecycleRecords = try [
            prefix + "family.leave.tombstone": mutationRecordData(
                value: "leave-tombstone",
                createdAt: currentTime.addingTimeInterval(-retention - 1)
            ),
            prefix + "account.delete.tombstone": mutationRecordData(
                value: "delete-tombstone",
                createdAt: currentTime.addingTimeInterval(-retention - 1)
            ),
        ]
        for (storageKey, record) in lifecycleRecords {
            defaults.set(record, forKey: storageKey)
        }

        let client = try makeClient(
            transport: ScriptedHTTPTransport(steps: []),
            authenticated: false,
            idempotencyDefaults: defaults,
            now: { currentTime }
        )
        do {
            _ = try await client.hasStoredSession()
        } catch {
            // Durable lifecycle fixtures intentionally have no HTTP response;
            // the secure-state sweep happens before reconciliation reaches it.
        }

        for storageKey in expiredKeys {
            XCTAssertNil(
                defaults.data(forKey: storageKey),
                "Expired bounded record was not pruned: \(storageKey)"
            )
        }
        for (storageKey, record) in activeRecords {
            XCTAssertEqual(defaults.data(forKey: storageKey), record)
        }
        for (storageKey, record) in lifecycleRecords {
            XCTAssertEqual(
                defaults.data(forKey: storageKey),
                record,
                "Lifecycle tombstone must not use the 30-day privacy window"
            )
        }
    }

    func testMutationUseSweepsUnrelatedExpiredDigestAndRetainsActiveState() async throws {
        let suiteName = "tsutsuura.tests.mutation-use-prune.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let currentTime = Date(timeIntervalSince1970: 1_788_192_000)
        let retention: TimeInterval = 30 * 24 * 60 * 60
        let prefix = "tsutsuura.idempotency.v1."
        let transport = ScriptedHTTPTransport(steps: [
            .urlError(.networkConnectionLost),
        ])
        let client = try makeClient(
            transport: transport,
            authenticated: false,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            now: { currentTime }
        )

        let expiredKey = prefix + "family.create.unrelated-expired-digest"
        let activeKey = prefix + "comment.reply.active-digest"
        let leaveKey = prefix + "family.leave.tombstone"
        let deleteKey = prefix + "account.delete.tombstone"
        let expiredRecord = try mutationRecordData(
            value: "expired-family-create",
            createdAt: currentTime.addingTimeInterval(-retention - 1)
        )
        let activeRecord = try mutationRecordData(
            value: "active-comment-reply",
            createdAt: currentTime.addingTimeInterval(-60)
        )
        let lifecycleRecord = try mutationRecordData(
            value: "durable-lifecycle-receipt",
            createdAt: currentTime.addingTimeInterval(-retention - 1)
        )
        defaults.set(expiredRecord, forKey: expiredKey)
        defaults.set(activeRecord, forKey: activeKey)
        defaults.set(lifecycleRecord, forKey: leaveKey)
        defaults.set(lifecycleRecord, forKey: deleteKey)

        do {
            _ = try await client.verifyOTP(
                requestID: String(repeating: "e", count: 32),
                code: "123456"
            )
            XCTFail("The verification response must be lost")
        } catch {}

        XCTAssertNil(defaults.data(forKey: expiredKey))
        XCTAssertEqual(defaults.data(forKey: activeKey), activeRecord)
        XCTAssertEqual(defaults.data(forKey: leaveKey), lifecycleRecord)
        XCTAssertEqual(defaults.data(forKey: deleteKey), lifecycleRecord)
    }

    func testManagedMemberDeleteReconcilesCommittedLostResponseWithAbsentMember() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: familyPayload(ownerID: "user-1")),
            .urlError(.networkConnectionLost),
            .response(
                statusCode: 404,
                data: notFoundPayload(code: "family_member_not_found")
            ),
            .response(
                statusCode: 200,
                data: familyPayload(
                    ownerID: "user-1",
                    includesManagedMember: false
                )
            ),
        ])
        let client = try makeClient(transport: transport)

        try await client.removeManagedFamilyMember(memberID: "user-2")

        let methods = await transport.methods
        let paths = await transport.paths
        XCTAssertEqual(methods, ["GET", "DELETE", "DELETE", "GET"])
        XCTAssertEqual(
            paths,
            [
                "/v1/family",
                "/v1/family/members/user-2",
                "/v1/family/members/user-2",
                "/v1/family",
            ]
        )
    }

    func testAnswerDeleteReconcilesCommittedLostResponseWithAbsentAnswer() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: answerPayload),
            .urlError(.networkConnectionLost),
            .response(
                statusCode: 404,
                data: notFoundPayload(code: "answer_not_found")
            ),
            .response(
                statusCode: 404,
                data: notFoundPayload(code: "answer_not_found")
            ),
        ])
        let client = try makeClient(transport: transport)

        try await client.deleteAnswer(answerID: "10")

        let methods = await transport.methods
        let paths = await transport.paths
        XCTAssertEqual(methods, ["GET", "DELETE", "DELETE", "GET"])
        XCTAssertEqual(
            paths,
            [
                "/v1/answers/10",
                "/v1/answers/10",
                "/v1/answers/10",
                "/v1/answers/10",
            ]
        )
    }

    func testAnswerMediaDeleteReconcilesCommittedLostResponseWithRefreshedAnswer() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: answerPayload(mediaIDs: ["media-1"])
            ),
            .urlError(.networkConnectionLost),
            .response(
                statusCode: 404,
                data: notFoundPayload(code: "media_not_found")
            ),
            .response(statusCode: 200, data: answerPayload),
        ])
        let client = try makeClient(transport: transport)

        let refreshedAnswer = try await client.deleteAnswerMedia(
            answerID: "10",
            mediaID: "media-1"
        )

        XCTAssertEqual(refreshedAnswer.id, "10")
        XCTAssertTrue(refreshedAnswer.media.isEmpty)
        let methods = await transport.methods
        let paths = await transport.paths
        XCTAssertEqual(methods, ["GET", "DELETE", "DELETE", "GET"])
        XCTAssertEqual(
            paths,
            [
                "/v1/answers/10",
                "/v1/answers/10/media/media-1",
                "/v1/answers/10/media/media-1",
                "/v1/answers/10",
            ]
        )
    }

    func testCommentDeleteReconcilesCommittedLostResponseWithAbsentComment() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: commentsPayload(
                    commentIDs: ["comment-1"],
                    answerID: "answer-1"
                )
            ),
            .urlError(.networkConnectionLost),
            .response(
                statusCode: 404,
                data: notFoundPayload(code: "comment_not_found")
            ),
            .response(
                statusCode: 200,
                data: commentsPayload(commentIDs: [], answerID: "answer-1")
            ),
        ])
        let client = try makeClient(transport: transport)

        try await client.deleteComment(
            commentID: "comment-1",
            answerID: "answer-1"
        )

        let methods = await transport.methods
        let paths = await transport.paths
        XCTAssertEqual(methods, ["GET", "DELETE", "DELETE", "GET"])
        XCTAssertEqual(
            paths,
            [
                "/v1/answers/answer-1/comments",
                "/v1/comments/comment-1",
                "/v1/comments/comment-1",
                "/v1/answers/answer-1/comments",
            ]
        )
    }

    func testDeleteReconciliationPreservesAuthorizationFailures() async throws {
        let answerTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: answerPayload),
            .response(
                statusCode: 404,
                data: notFoundPayload(code: "answer_not_found")
            ),
            .response(statusCode: 200, data: answerPayload),
        ])
        let answerClient = try makeClient(transport: answerTransport)

        do {
            try await answerClient.deleteAnswer(answerID: "10")
            XCTFail("A still-visible answer must retain the ownership failure")
        } catch let APIClientError.server(statusCode, _) {
            XCTAssertEqual(statusCode, 404)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let answerMethods = await answerTransport.methods
        XCTAssertEqual(answerMethods, ["GET", "DELETE", "GET"])

        let mediaTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: answerPayload(mediaIDs: ["media-1"])
            ),
            .response(
                statusCode: 404,
                data: notFoundPayload(code: "answer_not_found")
            ),
            .response(
                statusCode: 200,
                data: answerPayload(mediaIDs: ["media-1"])
            ),
        ])
        let mediaClient = try makeClient(transport: mediaTransport)

        do {
            _ = try await mediaClient.deleteAnswerMedia(
                answerID: "10",
                mediaID: "media-1"
            )
            XCTFail("Still-visible media must retain the ownership failure")
        } catch let APIClientError.server(statusCode, _) {
            XCTAssertEqual(statusCode, 404)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let mediaMethods = await mediaTransport.methods
        XCTAssertEqual(mediaMethods, ["GET", "DELETE", "GET"])

        let commentTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: commentsPayload(
                    commentIDs: ["comment-1"],
                    answerID: "answer-1"
                )
            ),
            .response(
                statusCode: 404,
                data: notFoundPayload(code: "comment_not_found")
            ),
            .response(
                statusCode: 200,
                data: commentsPayload(
                    commentIDs: ["comment-1"],
                    answerID: "answer-1"
                )
            ),
        ])
        let commentClient = try makeClient(transport: commentTransport)

        do {
            try await commentClient.deleteComment(
                commentID: "comment-1",
                answerID: "answer-1"
            )
            XCTFail("A still-visible comment must retain the ownership failure")
        } catch let APIClientError.server(statusCode, _) {
            XCTAssertEqual(statusCode, 404)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let commentMethods = await commentTransport.methods
        XCTAssertEqual(commentMethods, ["GET", "DELETE", "GET"])

        let memberTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 200, data: familyPayload(ownerID: "user-2")),
            .response(
                statusCode: 403,
                data: Data(
                    #"{"error":{"code":"family_owner_required","message":"owner only"}}"#.utf8
                )
            ),
        ])
        let memberClient = try makeClient(transport: memberTransport)

        do {
            try await memberClient.removeManagedFamilyMember(memberID: "user-2")
            XCTFail("An explicit owner authorization failure must be preserved")
        } catch let APIClientError.server(statusCode, _) {
            XCTAssertEqual(statusCode, 403)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let memberMethods = await memberTransport.methods
        XCTAssertEqual(memberMethods, ["GET", "DELETE"])
    }

    func testGETRetriesTransientTransportAndServerFailuresThenSucceeds() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .urlError(.timedOut),
            .response(statusCode: 503, data: serverErrorPayload),
            .response(statusCode: 200, data: userPayload),
        ])
        let client = try makeClient(transport: transport)

        let profile = try await client.fetchMe()
        let requestCount = await transport.requestCount
        let methods = await transport.methods

        XCTAssertEqual(profile.id, "user-1")
        XCTAssertEqual(requestCount, 3)
        XCTAssertEqual(methods, ["GET", "GET", "GET"])
    }

    func testPUTAndDELETERetryTransientFailures() async throws {
        let putTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 500, data: serverErrorPayload),
            .response(statusCode: 200, data: answerPayload),
        ])
        let putClient = try makeClient(transport: putTransport)

        _ = try await putClient.submitAnswer(questionID: "question-1", body: "回答")
        let putRequestCount = await putTransport.requestCount
        let putMethods = await putTransport.methods
        XCTAssertEqual(putRequestCount, 2)
        XCTAssertEqual(putMethods, ["PUT", "PUT"])

        let deleteTransport = ScriptedHTTPTransport(steps: [
            .response(
                statusCode: 200,
                data: commentsPayload(
                    commentIDs: ["comment-1"],
                    answerID: "answer-1"
                )
            ),
            .urlError(.networkConnectionLost),
            .response(statusCode: 200, data: emptyPayload),
        ])
        let deleteClient = try makeClient(transport: deleteTransport)

        try await deleteClient.deleteComment(
            commentID: "comment-1",
            answerID: "answer-1"
        )
        let deleteRequestCount = await deleteTransport.requestCount
        let deleteMethods = await deleteTransport.methods
        XCTAssertEqual(deleteRequestCount, 3)
        XCTAssertEqual(deleteMethods, ["GET", "DELETE", "DELETE"])
    }

    func testRetryAttemptsAreBounded() async throws {
        let transport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 503, data: serverErrorPayload),
            .response(statusCode: 503, data: serverErrorPayload),
            .response(statusCode: 503, data: serverErrorPayload),
            .response(statusCode: 200, data: userPayload),
        ])
        let client = try makeClient(transport: transport)

        do {
            _ = try await client.fetchMe()
            XCTFail("A fourth attempt must not be made")
        } catch let APIClientError.server(statusCode, _) {
            XCTAssertEqual(statusCode, 503)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 3)
    }

    func testDoesNotRetryPOSTPATCHOrMultipartRequests() async throws {
        let postTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 503, data: serverErrorPayload),
            .response(statusCode: 200, data: otpPayload),
        ])
        let postClient = try makeClient(
            transport: postTransport,
            authenticated: false
        )
        do {
            _ = try await postClient.requestOTP(phoneNumber: "+819012345678")
            XCTFail("POST must not retry")
        } catch {}
        let postRequestCount = await postTransport.requestCount
        XCTAssertEqual(postRequestCount, 1)

        let patchTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 503, data: serverErrorPayload),
            .response(statusCode: 200, data: userPayload),
        ])
        let patchClient = try makeClient(transport: patchTransport)
        do {
            _ = try await patchClient.updateProfile(displayName: "かえで")
            XCTFail("PATCH must not retry")
        } catch {}
        let patchRequestCount = await patchTransport.requestCount
        XCTAssertEqual(patchRequestCount, 1)

        let multipartTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 503, data: serverErrorPayload),
            .response(statusCode: 200, data: answerPayload),
        ])
        let multipartClient = try makeClient(transport: multipartTransport)
        do {
            _ = try await multipartClient.submitAnswer(
                questionID: "question-1",
                submission: AnswerSubmission(
                    body: "写真",
                    photos: [
                        AnswerMediaUpload(
                            data: Data([0x01]),
                            fileName: "photo.jpg",
                            mimeType: "image/jpeg"
                        )
                    ]
                )
            )
            XCTFail("Multipart POST must not retry")
        } catch {}
        let multipartRequestCount = await multipartTransport.requestCount
        XCTAssertEqual(multipartRequestCount, 1)
    }

    func testDoesNotRetry4xxOrNonTransientTransportErrors() async throws {
        let clientErrorTransport = ScriptedHTTPTransport(steps: [
            .response(statusCode: 429, data: serverErrorPayload),
            .response(statusCode: 200, data: userPayload),
        ])
        let clientErrorClient = try makeClient(transport: clientErrorTransport)
        do {
            _ = try await clientErrorClient.fetchMe()
            XCTFail("4xx responses must not retry")
        } catch {}
        let clientErrorRequestCount = await clientErrorTransport.requestCount
        XCTAssertEqual(clientErrorRequestCount, 1)

        let badURLTransport = ScriptedHTTPTransport(steps: [
            .urlError(.badURL),
            .response(statusCode: 200, data: userPayload),
        ])
        let badURLClient = try makeClient(transport: badURLTransport)
        do {
            _ = try await badURLClient.fetchMe()
            XCTFail("A non-transient URL error must not retry")
        } catch {}
        let badURLRequestCount = await badURLTransport.requestCount
        XCTAssertEqual(badURLRequestCount, 1)
    }

    private func makeClient(
        transport: ScriptedHTTPTransport,
        authenticated: Bool = true,
        tokenStore: InMemoryTokenStore? = nil,
        retryPolicy: APIRequestRetryPolicy = APIRequestRetryPolicy(
            maximumAttempts: 3,
            initialDelay: 0,
            maximumDelay: 0
        ),
        idempotencyDefaults: UserDefaults = .standard,
        mutationProtectionKey: Data = Data(repeating: 0x5A, count: 32),
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> DefaultAppAPI {
        DefaultAppAPI(
            configuration: try APIConfiguration(
                baseURL: try XCTUnwrap(URL(string: "https://api.example.com"))
            ),
            transport: transport,
            tokenStore: tokenStore ?? InMemoryTokenStore(
                token: authenticated ? "token" : nil
            ),
            retryPolicy: retryPolicy,
            idempotencyDefaults: idempotencyDefaults,
            mutationProtectionKey: mutationProtectionKey,
            now: now
        )
    }

    private func mutationRecordData(
        value: String,
        createdAt: Date
    ) throws -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try JSONSerialization.data(
            withJSONObject: [
                "value": value,
                "createdAt": formatter.string(from: createdAt),
            ]
        )
    }

    private var userPayload: Data {
        return Data(
            #"{"data":{"id":"user-1","displayName":"かえで","avatarUrl":null,"hasPhone":true,"managed":false,"createdAt":"2026-07-28T01:00:00Z"}}"#.utf8
        )
    }

    private func authPayload(token: String) -> Data {
        Data(
            """
            {"data":{"token":"\(token)","tokenType":"Bearer","expiresAt":"2026-10-01T00:00:00Z","user":{"id":"user-1","displayName":"かえで","avatarUrl":null,"hasPhone":true,"managed":false,"createdAt":"2026-07-28T01:00:00Z"}}}
            """.utf8
        )
    }

    private var pairingPreviewPayload: Data {
        Data(
            """
            {"data":{"pairing":{"id":"pairing-1","expiresAt":"2026-10-01T00:00:00Z","createdAt":"2026-09-01T00:00:00Z","status":"consumed","member":{"id":"user-1","displayName":"おばあちゃん"},"family":{"id":"family-1","name":"つつうら家"}}}}
            """.utf8
        )
    }

    private var pendingPairingPreviewPayload: Data {
        Data(
            """
            {"data":{"pairing":{"id":"pairing-2","expiresAt":"2026-10-01T00:00:00Z","createdAt":"2026-09-01T00:00:00Z","status":"pending","member":{"id":"user-2","displayName":"おじいちゃん"},"family":{"id":"family-2","name":"別の家族"}}}}
            """.utf8
        )
    }

    private var managedMemberPayload: Data {
        Data(
            #"{"data":{"member":{"id":"managed-1","displayName":"おばあちゃん","avatarUrl":null,"hasPhone":false,"managed":true,"createdAt":"2026-09-01T00:00:00Z"}}}"#.utf8
        )
    }

    private func createdCommentPayload(
        id: String,
        answerID: String,
        body: String
    ) -> Data {
        Data(
            """
            {"data":{"comment":{"id":"\(id)","answerId":"\(answerID)","author":{"id":"user-1","displayName":"かえで","avatarUrl":null},"body":"\(body)","createdAt":"2026-07-28T01:00:00Z","updatedAt":"2026-07-28T01:00:00Z","parentCommentId":null}}}
            """.utf8
        )
    }

    private var answerPayload: Data {
        answerPayload(mediaIDs: [])
    }

    private func answerPayload(mediaIDs: [String]) -> Data {
        let media = mediaIDs.map { mediaID in
            """
            {"id":"\(mediaID)","kind":"photo","url":"https://api.example.com/v1/answer-media/\(mediaID)/token","mimeType":"image/jpeg","fileName":"memory.jpg","byteCount":12,"durationMilliseconds":null}
            """
        }.joined(separator: ",")
        return Data(
            """
            {"data":{"answer":{"id":"10","answerDate":"2026-07-28","body":"回答","question":{"id":"7","prompt":"質問","date":"2026-07-28"},"author":{"id":"1","displayName":"かえで","avatarUrl":null},"likesCount":0,"isLiked":false,"commentsCount":0,"media":[\(media)],"createdAt":"2026-07-28T01:00:00Z","updatedAt":"2026-07-28T01:00:00Z"}}}
            """.utf8
        )
    }

    private func commentsPayload(
        commentIDs: [String],
        answerID: String,
        nextCursor: String? = nil
    ) -> Data {
        let comments = commentIDs.map { commentID in
            """
            {"id":"\(commentID)","answerId":"\(answerID)","author":{"id":"user-1","displayName":"かえで","avatarUrl":null},"body":"コメント","createdAt":"2026-07-28T01:00:00Z","updatedAt":null,"parentCommentId":null}
            """
        }.joined(separator: ",")
        let encodedCursor = nextCursor.map { "\"\($0)\"" } ?? "null"
        return Data(
            """
            {"data":{"items":[\(comments)],"nextCursor":\(encodedCursor)}}
            """.utf8
        )
    }

    private var otpPayload: Data {
        Data(#"{"data":{"requestId":"otp-1","expiresIn":300}}"#.utf8)
    }

    private var emptyPayload: Data { Data(#"{"data":{}}"#.utf8) }

    private func familyPayload(
        id: String = "family-1",
        ownerID: String,
        includesManagedMember: Bool = true
    ) -> Data {
        let firstRole = ownerID == "user-1" ? "owner" : "member"
        let secondRole = ownerID == "user-2" ? "owner" : "member"
        let secondMember = includesManagedMember
            ? """
              ,{"id":"user-2","displayName":"あおい","avatarUrl":null,"hasPhone":false,"managed":true,"role":"\(secondRole)"}
              """
            : ""
        let memberCount = includesManagedMember ? 2 : 1
        return Data(
            """
            {"data":{"id":"\(id)","name":"家族","memberCount":\(memberCount),"members":[
              {"id":"user-1","displayName":"かえで","avatarUrl":null,"hasPhone":true,"managed":false,"role":"\(firstRole)"}\(secondMember)
            ]}}
            """.utf8
        )
    }

    private func notFoundPayload(code: String) -> Data {
        Data(
            """
            {"error":{"code":"\(code)","message":"not found"}}
            """.utf8
        )
    }

    private var serverErrorPayload: Data {
        Data(
            #"{"error":{"code":"temporarily_unavailable","message":"retry"}}"#.utf8
        )
    }
}

@MainActor
final class AppStoreRoutingTests: XCTestCase {
    func testRequestingOTPRoutesToTypedVerificationRoute() async {
        let api = StubAppAPI(
            storedSession: false,
            otpChallenge: OTPChallenge(requestID: "request-42", expiresIn: 300)
        )
        let store = AppStore(api: api, haptics: NoopHaptics())
        store.auth.phoneNumber = "+81 90 1234 5678"

        await store.requestOTP()

        XCTAssertEqual(
            store.session,
            .awaitingOTP(phoneNumber: "+819012345678")
        )
        XCTAssertEqual(
            store.path,
            [
                .otpVerification(
                    phoneNumber: "+819012345678",
                    requestID: "request-42"
                )
            ]
        )
    }

    func testLoginChallengeRestoresAfterProcessRelaunchWithoutPersistingCode() async throws {
        let suiteName = "tsutsuura.tests.login-challenge-relaunch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let challenge = OTPChallenge(requestID: "request-relaunch", expiresIn: 300)
        let firstStore = AppStore(
            api: StubAppAPI(storedSession: false, otpChallenge: challenge),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt }
        )
        firstStore.auth.phoneNumber = "09012345678"
        _ = await firstStore.requestOTP()
        firstStore.auth.verificationCode = "123456"

        let relaunchedStore = AppStore(
            api: StubAppAPI(storedSession: false, otpChallenge: challenge),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt.addingTimeInterval(60) }
        )
        await relaunchedStore.restoreSession()

        XCTAssertEqual(
            relaunchedStore.session,
            .awaitingOTP(phoneNumber: "+819012345678")
        )
        XCTAssertEqual(relaunchedStore.auth.challenge?.requestID, "request-relaunch")
        XCTAssertEqual(relaunchedStore.auth.verificationCode, "")
        XCTAssertEqual(
            relaunchedStore.path,
            [
                .otpVerification(
                    phoneNumber: "+819012345678",
                    requestID: "request-relaunch"
                )
            ]
        )
        XCTAssertEqual(
            relaunchedStore.auth.expiresAt,
            startedAt.addingTimeInterval(300)
        )
    }

    func testExpiredLoginChallengeIsDiscardedOnRelaunch() async throws {
        let suiteName = "tsutsuura.tests.login-challenge-expiry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let challenge = OTPChallenge(requestID: "request-expired", expiresIn: 300)
        let firstStore = AppStore(
            api: StubAppAPI(storedSession: false, otpChallenge: challenge),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt }
        )
        firstStore.auth.phoneNumber = "09012345678"
        _ = await firstStore.requestOTP()

        let relaunchedStore = AppStore(
            api: StubAppAPI(storedSession: false, otpChallenge: challenge),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt.addingTimeInterval(301) }
        )
        await relaunchedStore.restoreSession()

        XCTAssertEqual(relaunchedStore.session, .signedOut)
        XCTAssertEqual(relaunchedStore.path, [.onboarding])
        XCTAssertNil(relaunchedStore.auth.challenge)
    }

    func testInterruptedLoginVerificationRemainsReplayableAfterChallengeExpiry()
    async throws {
        let suiteName = "tsutsuura.tests.login-attempt-replay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let challenge = OTPChallenge(
            requestID: "request-interrupted",
            expiresIn: 300
        )
        let firstStore = AppStore(
            api: StubAppAPI(storedSession: false, otpChallenge: challenge),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt }
        )
        firstStore.auth.phoneNumber = "09012345678"
        _ = await firstStore.requestOTP()
        firstStore.auth.verificationCode = "123456"

        // The stub throws an indeterminate local error, representing a
        // response that may have been lost after the server committed.
        await firstStore.verifyOTP()

        let relaunchedStore = AppStore(
            api: StubAppAPI(storedSession: false, otpChallenge: challenge),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt.addingTimeInterval(301) }
        )
        await relaunchedStore.restoreSession()

        XCTAssertEqual(
            relaunchedStore.session,
            .awaitingOTP(phoneNumber: "+819012345678")
        )
        XCTAssertEqual(
            relaunchedStore.auth.challenge?.requestID,
            "request-interrupted"
        )
        XCTAssertEqual(relaunchedStore.auth.verificationCode, "")
        XCTAssertEqual(
            relaunchedStore.auth.expiresAt,
            startedAt.addingTimeInterval(300)
        )
        XCTAssertTrue(relaunchedStore.auth.canReplayExpiredAttempt)
    }

    func testValidSessionRestoreClearsCompletedLoginCrashRecord() async throws {
        let suiteName = "tsutsuura.tests.login-crash-self-heal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let challenge = OTPChallenge(
            requestID: "request-completed-before-crash",
            expiresIn: 300
        )
        let firstStore = AppStore(
            api: StubAppAPI(storedSession: false, otpChallenge: challenge),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt }
        )
        firstStore.auth.phoneNumber = "09012345678"
        _ = await firstStore.requestOTP()

        let profile = UserProfile(
            id: "user-completed-login",
            displayName: "かえで",
            avatarURL: nil,
            phoneNumber: "09012345678",
            family: nil,
            hasPhone: true
        )
        let relaunchedStore = AppStore(
            api: StubAppAPI(storedSession: true, fetchedUser: profile),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt.addingTimeInterval(30) }
        )
        await relaunchedStore.restoreSession()
        XCTAssertEqual(relaunchedStore.session, .signedIn(profile))

        await relaunchedStore.signOut()

        XCTAssertEqual(relaunchedStore.session, .signedOut)
        XCTAssertEqual(relaunchedStore.path, [.onboarding])
        XCTAssertNil(relaunchedStore.auth.challenge)
    }

    func testPhoneEnrollmentChallengeRestoresOnlyForSameSignedInActor() async throws {
        let suiteName = "tsutsuura.tests.enrollment-challenge-relaunch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let profile = UserProfile(
            id: "user-enrollment",
            displayName: "かえで",
            avatarURL: nil,
            phoneNumber: nil,
            family: nil
        )
        let challenge = OTPChallenge(
            requestID: "enrollment-relaunch",
            expiresIn: 300
        )
        let firstStore = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUser: profile,
                otpChallenge: challenge
            ),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt }
        )
        await firstStore.restoreSession()
        firstStore.phoneEnrollment.phoneNumber = "08012345678"
        _ = await firstStore.requestPhoneEnrollment()
        firstStore.phoneEnrollment.verificationCode = "654321"

        let relaunchedStore = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUser: profile,
                otpChallenge: challenge
            ),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt.addingTimeInterval(60) }
        )
        await relaunchedStore.restoreSession()

        XCTAssertEqual(relaunchedStore.session, .signedIn(profile))
        XCTAssertEqual(
            relaunchedStore.phoneEnrollment.challenge?.requestID,
            "enrollment-relaunch"
        )
        XCTAssertEqual(relaunchedStore.phoneEnrollment.verificationCode, "")
        XCTAssertEqual(
            relaunchedStore.path.last,
            .phoneEnrollmentVerification(
                phoneNumber: "+818012345678",
                requestID: "enrollment-relaunch"
            )
        )
        XCTAssertEqual(
            relaunchedStore.phoneEnrollment.expiresAt,
            startedAt.addingTimeInterval(300)
        )

        let otherProfile = UserProfile(
            id: "different-user",
            displayName: profile.displayName,
            avatarURL: profile.avatarURL,
            phoneNumber: profile.phoneNumber,
            family: profile.family
        )
        let otherActorStore = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUser: otherProfile,
                otpChallenge: challenge
            ),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt.addingTimeInterval(60) }
        )
        await otherActorStore.restoreSession()
        XCTAssertNil(otherActorStore.phoneEnrollment.challenge)
        XCTAssertEqual(otherActorStore.path, [.home])
    }

    func testInterruptedEnrollmentVerificationRemainsReplayableAfterExpiry()
    async throws {
        let suiteName = "tsutsuura.tests.enrollment-attempt-replay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let profile = UserProfile(
            id: "user-enrollment-interrupted",
            displayName: "かえで",
            avatarURL: nil,
            phoneNumber: nil,
            family: nil,
            hasPhone: false
        )
        let challenge = OTPChallenge(
            requestID: "enrollment-interrupted",
            expiresIn: 300
        )
        let firstStore = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUser: profile,
                otpChallenge: challenge
            ),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt }
        )
        await firstStore.restoreSession()
        firstStore.phoneEnrollment.phoneNumber = "08012345678"
        _ = await firstStore.requestPhoneEnrollment()
        firstStore.phoneEnrollment.verificationCode = "654321"

        let didVerify = await firstStore.verifyPhoneEnrollment()
        XCTAssertFalse(didVerify)

        let relaunchedStore = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUser: profile,
                otpChallenge: challenge
            ),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt.addingTimeInterval(301) }
        )
        await relaunchedStore.restoreSession()

        XCTAssertEqual(
            relaunchedStore.phoneEnrollment.challenge?.requestID,
            "enrollment-interrupted"
        )
        XCTAssertEqual(relaunchedStore.phoneEnrollment.verificationCode, "")
        XCTAssertEqual(
            relaunchedStore.phoneEnrollment.expiresAt,
            startedAt.addingTimeInterval(300)
        )
        XCTAssertTrue(
            relaunchedStore.phoneEnrollment.canReplayExpiredAttempt
        )
        XCTAssertEqual(
            relaunchedStore.path.last,
            .phoneEnrollmentVerification(
                phoneNumber: "+818012345678",
                requestID: "enrollment-interrupted"
            )
        )
    }

    func testMatchingFetchedPhoneClearsCompletedEnrollmentCrashRecord()
    async throws {
        let suiteName = "tsutsuura.tests.enrollment-crash-self-heal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 1_788_192_000)
        let initialProfile = UserProfile(
            id: "user-enrollment-crash",
            displayName: "かえで",
            avatarURL: nil,
            phoneNumber: nil,
            family: nil,
            hasPhone: false
        )
        let challenge = OTPChallenge(
            requestID: "enrollment-completed-before-crash",
            expiresIn: 300
        )
        let firstStore = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUser: initialProfile,
                otpChallenge: challenge
            ),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt }
        )
        await firstStore.restoreSession()
        firstStore.phoneEnrollment.phoneNumber = "08012345678"
        _ = await firstStore.requestPhoneEnrollment()

        var enrolledProfile = initialProfile
        enrolledProfile.phoneNumber = "080-1234-5678"
        enrolledProfile.hasPhone = true
        let relaunchedStore = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUser: enrolledProfile,
                otpChallenge: challenge
            ),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt.addingTimeInterval(30) }
        )
        await relaunchedStore.restoreSession()

        XCTAssertEqual(relaunchedStore.session, .signedIn(enrolledProfile))
        XCTAssertNil(relaunchedStore.phoneEnrollment.challenge)
        XCTAssertEqual(relaunchedStore.path, [.home])

        let thirdStore = AppStore(
            api: StubAppAPI(storedSession: true, fetchedUser: initialProfile),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { startedAt.addingTimeInterval(60) }
        )
        await thirdStore.restoreSession()
        XCTAssertNil(thirdStore.phoneEnrollment.challenge)
        XCTAssertEqual(thirdStore.path, [.home])
    }

    func testCancellingOTPKeepsReturningUserLoginReachable() async {
        let api = StubAppAPI(
            storedSession: false,
            otpChallenge: OTPChallenge(requestID: "request-42", expiresIn: 300)
        )
        let store = AppStore(api: api, haptics: NoopHaptics())
        store.auth.phoneNumber = "09012345678"
        await store.requestOTP()
        store.auth.verificationCode = "123"

        store.cancelOTP()

        XCTAssertEqual(store.session, .signedOut)
        XCTAssertEqual(store.path, [.onboarding, .phoneEntry])
        XCTAssertEqual(store.auth.verificationCode, "")
        XCTAssertNil(store.auth.challenge)
    }

    func testMissingStoredSessionRoutesToOnboarding() async {
        let store = AppStore(
            api: StubAppAPI(storedSession: false),
            haptics: NoopHaptics()
        )

        await store.restoreSession()

        XCTAssertEqual(store.session, .signedOut)
        XCTAssertEqual(store.path, [.onboarding])
    }

    func testSecureStoreReadFailureKeepsSessionRestoreRetryable() async {
        let store = AppStore(
            api: StubAppAPI(
                storedSession: false,
                throwsOnSessionRead: true
            ),
            haptics: NoopHaptics()
        )

        await store.restoreSession()

        XCTAssertEqual(store.session, .restoring)
        XCTAssertTrue(store.path.isEmpty)
        XCTAssertTrue(store.canRetrySessionRestore)
        XCTAssertNotNil(store.globalErrorMessage)
    }

    func testTransientProfileFailureKeepsSessionRestorable() async {
        let profile = UserProfile(
            id: "user-1",
            displayName: "かえで",
            avatarURL: nil,
            phoneNumber: nil,
            family: nil
        )
        let store = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUser: profile,
                fetchMeFailuresRemaining: 1
            ),
            haptics: NoopHaptics()
        )

        await store.restoreSession()

        XCTAssertEqual(store.session, .restoring)
        XCTAssertTrue(store.canRetrySessionRestore)
        XCTAssertNotNil(store.globalErrorMessage)

        await store.restoreSession()

        XCTAssertEqual(store.session, .signedIn(profile))
        XCTAssertFalse(store.canRetrySessionRestore)
    }

    func testRefreshReconcilesSuccessorManagedStateAndOwnershipRole() async {
        let userID = "successor-1"
        let joinedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let oldMember = UserProfile(
            id: userID,
            displayName: "あおい",
            avatarURL: nil,
            phoneNumber: nil,
            family: nil,
            hasPhone: false,
            managed: true,
            familyRole: .member,
            joinedAt: joinedAt
        )
        let newMember = UserProfile(
            id: userID,
            displayName: "あおい",
            avatarURL: nil,
            phoneNumber: nil,
            family: nil,
            hasPhone: false,
            managed: false,
            familyRole: .owner,
            joinedAt: joinedAt
        )
        let oldFamily = FamilySummary(
            id: "family-1",
            name: "家族",
            memberCount: 1,
            members: [oldMember]
        )
        let newFamily = FamilySummary(
            id: "family-1",
            name: "家族",
            memberCount: 1,
            members: [newMember]
        )
        var restoredProfile = oldMember
        restoredProfile.family = oldFamily
        var oldMe = oldMember
        oldMe.familyRole = nil
        oldMe.joinedAt = nil
        var promotedMe = newMember
        promotedMe.familyRole = nil
        promotedMe.joinedAt = nil

        let store = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUsers: [restoredProfile, oldMe, promotedMe],
                homeFeeds: [
                    HomeFeed(family: oldFamily),
                    HomeFeed(family: newFamily),
                ]
            ),
            haptics: NoopHaptics()
        )
        await store.restoreSession()

        guard case .signedIn(let beforeRefresh) = store.session else {
            return XCTFail("Expected a restored successor session")
        }
        XCTAssertEqual(beforeRefresh.managed, true)
        XCTAssertEqual(beforeRefresh.familyRole, .member)

        await store.refreshHome()

        guard case .signedIn(let afterRefresh) = store.session else {
            return XCTFail("Expected successor session to remain signed in")
        }
        XCTAssertEqual(afterRefresh.managed, false)
        XCTAssertEqual(afterRefresh.familyRole, .owner)
        XCTAssertEqual(
            store.home.feed?.family?.members.first?.familyRole,
            .owner
        )
    }

    func testRefreshAllDataReportsPartialFailureInsteadOfSuccess() async {
        let profile = UserProfile(
            id: "user-1",
            displayName: "かえで",
            avatarURL: nil,
            phoneNumber: nil,
            family: nil
        )
        let store = AppStore(
            api: StubAppAPI(storedSession: true, fetchedUser: profile),
            haptics: NoopHaptics()
        )
        await store.restoreSession()

        let didRefresh = await store.refreshAllData()

        XCTAssertFalse(didRefresh)
        XCTAssertNotNil(store.home.errorMessage)
        XCTAssertNotNil(store.history.errorMessage)
    }

    func testHistoryCacheReconciliationSearchesAuthorDisplayName() async throws {
        let matchingAuthor = AnswerAuthor(
            id: "author-history",
            displayName: "おばあちゃん",
            avatarURL: nil
        )
        let submittedAnswer = Answer(
            id: "answer-history-author",
            questionID: "question-history-author",
            questionPrompt: "検索語を含まない質問",
            author: matchingAuthor,
            body: "検索語を含まない回答",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        var renamedAnswer = submittedAnswer
        renamedAnswer.author.displayName = "祖母"
        let api = StubAppAPI(
            storedSession: false,
            submittedAnswer: submittedAnswer,
            updatedAnswer: renamedAnswer
        )
        let store = AppStore(api: api, haptics: NoopHaptics())
        store.question.question = Question(
            id: submittedAnswer.questionID,
            prompt: submittedAnswer.questionPrompt ?? "",
            publishedOn: "2026-09-01",
            answer: nil
        )
        store.question.draft = submittedAnswer.body
        store.history.query = HistoryQuery(
            scope: .family,
            searchText: matchingAuthor.displayName
        )
        store.history.hasLoaded = true

        await store.submitAnswer()

        XCTAssertEqual(store.history.answers.map(\.id), [submittedAnswer.id])

        let didUpdate = await store.updateAnswer(
            answerID: submittedAnswer.id,
            submission: AnswerSubmission(body: renamedAnswer.body)
        )

        XCTAssertTrue(didUpdate)
        XCTAssertTrue(store.history.answers.isEmpty)
    }

    func testFailedLocalSignOutKeepsAuthenticatedSession() async {
        let profile = UserProfile(
            id: "user-1",
            displayName: "かえで",
            avatarURL: nil,
            phoneNumber: nil,
            family: nil
        )
        let store = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUser: profile,
                signOutFails: true
            ),
            haptics: NoopHaptics()
        )
        await store.restoreSession()

        await store.signOut()

        XCTAssertEqual(store.session, .signedIn(profile))
        XCTAssertNotNil(store.globalErrorMessage)
    }

    func testDismissPresentedErrorsClearsEverySurfacedStoreError() async {
        let profile = UserProfile(
            id: "user-1",
            displayName: "かえで",
            avatarURL: nil,
            phoneNumber: nil,
            family: nil
        )
        let store = AppStore(
            api: StubAppAPI(
                storedSession: true,
                fetchedUser: profile,
                signOutFails: true
            ),
            haptics: NoopHaptics()
        )
        await store.restoreSession()
        await store.signOut()

        store.auth.errorMessage = "auth"
        store.phoneEnrollment.errorMessage = "phone"
        store.recovery.errorMessage = "recovery"
        store.home.errorMessage = "home"
        store.question.errorMessage = "question"
        store.history.errorMessage = "history"
        store.familySetup.errorMessage = "family"
        store.familyLifecycle.errorMessage = "family-lifecycle"
        store.answerOwnership.errorMessage = "answer"
        store.notificationPreferences.errorMessage = "notifications"
        store.account.errorMessage = "account"
        var thread = CommentThreadState()
        thread.errorMessage = "comment"
        store.commentThreads["answer-1"] = thread

        store.dismissPresentedErrors(commentAnswerID: "answer-1")

        XCTAssertNil(store.globalErrorMessage)
        XCTAssertNil(store.auth.errorMessage)
        XCTAssertNil(store.phoneEnrollment.errorMessage)
        XCTAssertNil(store.recovery.errorMessage)
        XCTAssertNil(store.home.errorMessage)
        XCTAssertNil(store.question.errorMessage)
        XCTAssertNil(store.history.errorMessage)
        XCTAssertNil(store.familySetup.errorMessage)
        XCTAssertNil(store.familyLifecycle.errorMessage)
        XCTAssertNil(store.answerOwnership.errorMessage)
        XCTAssertNil(store.notificationPreferences.errorMessage)
        XCTAssertNil(store.account.errorMessage)
        XCTAssertNil(store.commentThreads["answer-1"]?.errorMessage)
    }

    func testCommentPushLoadsEveryPageUntilExactCommentIsFocused() async {
        let author = AnswerAuthor(
            id: "family-member",
            displayName: "あおい",
            avatarURL: nil
        )
        let answer = Answer(
            id: "answer-paged",
            questionID: "question-1",
            author: author,
            body: "家族の回答",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            commentCount: 3
        )
        func comment(_ id: String) -> Comment {
            Comment(
                id: id,
                answerID: answer.id,
                author: author,
                body: id,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }
        let api = StubAppAPI(
            storedSession: true,
            fetchedAnswer: answer,
            commentPages: [
                CommentPage(
                    comments: [comment("comment-1")],
                    nextCursor: "cursor-1"
                ),
                CommentPage(
                    comments: [comment("comment-2")],
                    nextCursor: "cursor-2"
                ),
                CommentPage(
                    comments: [comment("comment-target")],
                    nextCursor: nil
                ),
            ]
        )
        let store = AppStore(api: api, haptics: NoopHaptics())

        let didOpen = await store.openPushAnswer(
            answerID: answer.id,
            targetCommentID: "comment-target"
        )

        XCTAssertTrue(didOpen)
        XCTAssertEqual(
            store.commentThreads[answer.id]?.comments.map(\.id),
            ["comment-1", "comment-2", "comment-target"]
        )
        XCTAssertEqual(
            store.commentThreads[answer.id]?.focusedCommentID,
            "comment-target"
        )
        let observedCursors = await api.observedCommentCursors()
        XCTAssertEqual(
            observedCursors,
            [nil, "cursor-1", "cursor-2"]
        )
        XCTAssertEqual(
            store.path,
            [.home, .comments(answerID: answer.id)]
        )
    }

    func testPushCommentFailureRemainsDurableAcrossRelaunchThenAcknowledgesRetry() async throws {
        let suiteName = "tsutsuura-tests.push-retry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pending = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: "push-retry"
        )
        let author = AnswerAuthor(
            id: "author-1",
            displayName: "家族",
            avatarURL: nil
        )
        let answer = Answer(
            id: "answer-retry",
            questionID: "question-1",
            author: author,
            body: "回答",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            commentCount: 1
        )
        let target = Comment(
            id: "comment-retry",
            answerID: answer.id,
            author: author,
            body: "再試行後に表示",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let destination = AppPushDestination.comments(
            answerID: answer.id,
            commentID: target.id
        )
        let api = StubAppAPI(
            storedSession: true,
            fetchedAnswer: answer,
            commentPages: [CommentPage(comments: [target], nextCursor: nil)],
            commentFailuresRemaining: 1
        )
        let store = AppStore(api: api, haptics: NoopHaptics())
        await pending.save(destination)

        let firstDestination = await pending.peek()
        let firstOpened = await store.openPushAnswer(
            answerID: answer.id,
            targetCommentID: target.id
        )
        if firstOpened, let firstDestination {
            await pending.acknowledge(firstDestination)
        }
        XCTAssertFalse(firstOpened)

        let relaunchedPending = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: "push-retry"
        )
        let retryDestination = await relaunchedPending.peek()
        XCTAssertEqual(retryDestination, destination)
        let retryOpened = await store.openPushAnswer(
            answerID: answer.id,
            targetCommentID: target.id
        )
        if retryOpened, let retryDestination {
            await relaunchedPending.acknowledge(retryDestination)
        }
        XCTAssertTrue(retryOpened)

        let completedProcess = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: "push-retry"
        )
        let completedDestination = await completedProcess.peek()
        XCTAssertNil(completedDestination)
        XCTAssertEqual(
            store.commentThreads[answer.id]?.focusedCommentID,
            target.id
        )
        let cursors = await api.observedCommentCursors()
        XCTAssertEqual(cursors, [nil, nil])
    }

    func testDeletedAnswerPushIsTerminalAndAcknowledged() async throws {
        let suiteName = "tsutsuura-tests.push-deleted-answer.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pending = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: "deleted-answer"
        )
        let destination = AppPushDestination.familyAnswer(
            answerID: "deleted-answer"
        )
        let api = StubAppAPI(
            storedSession: true,
            answerIsMissing: true
        )
        let store = AppStore(api: api, haptics: NoopHaptics())
        await pending.save(destination)

        let didHandle = await store.openPushAnswer(
            answerID: "deleted-answer"
        )
        if didHandle {
            await pending.acknowledge(destination)
        }

        XCTAssertTrue(didHandle)
        let remainingDestination = await pending.peek()
        XCTAssertNil(remainingDestination)
        XCTAssertEqual(
            store.globalErrorMessage,
            "この回答は削除されたか、現在は表示できません。"
        )
    }

    func testUnavailableTodayQuestionPushIsTerminalAndAcknowledged() async throws {
        let suiteName = "tsutsuura-tests.push-missing-question.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pending = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: "missing-question"
        )
        let destination = AppPushDestination.todayQuestion(questionID: nil)
        let api = StubAppAPI(
            storedSession: true,
            todayQuestionIsMissing: true
        )
        let store = AppStore(api: api, haptics: NoopHaptics())
        await pending.save(destination)

        let resolution = await store.loadTodayQuestionForPush(
            expectedQuestionID: nil
        )
        if resolution != .retryable {
            await pending.acknowledge(destination)
        }

        XCTAssertEqual(resolution, .terminal)
        let remainingDestination = await pending.peek()
        XCTAssertNil(remainingDestination)
        XCTAssertNil(store.question.question)
        XCTAssertEqual(
            store.globalErrorMessage,
            "この質問は終了したか、現在は表示できません。"
        )
    }

    func testAnswerDeletedBetweenPushFetchAndCommentsIsTerminal() async throws {
        let author = AnswerAuthor(
            id: "author-race",
            displayName: "家族",
            avatarURL: nil
        )
        let answer = Answer(
            id: "answer-deleted-race",
            questionID: "question-1",
            author: author,
            body: "削除前の回答",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let api = StubAppAPI(
            storedSession: true,
            fetchedAnswer: answer,
            commentsAreMissing: true
        )
        let store = AppStore(api: api, haptics: NoopHaptics())

        let didHandle = await store.openPushAnswer(
            answerID: answer.id,
            targetCommentID: "deleted-comment"
        )

        XCTAssertTrue(didHandle)
        XCTAssertEqual(
            store.globalErrorMessage,
            "この回答は削除されたか、現在は表示できません。"
        )
        XCTAssertEqual(store.path, [])
    }

    func testStaleQuestionPushDoesNotOpenDifferentCurrentQuestion() async throws {
        let suiteName = "tsutsuura-tests.push-stale-question.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pending = PendingPushDestinationStore(
            defaults: defaults,
            storageKey: "stale-question"
        )
        let destination = AppPushDestination.todayQuestion(
            questionID: "question-yesterday"
        )
        let currentQuestion = Question(
            id: "question-today",
            prompt: "今日の質問",
            publishedOn: "2026-09-01",
            answer: nil
        )
        let api = StubAppAPI(
            storedSession: true,
            fetchedTodayQuestion: currentQuestion
        )
        let store = AppStore(api: api, haptics: NoopHaptics())
        await pending.save(destination)

        let resolution = await store.loadTodayQuestionForPush(
            expectedQuestionID: "question-yesterday"
        )
        if resolution != .retryable {
            await pending.acknowledge(destination)
        }

        XCTAssertEqual(resolution, .terminal)
        XCTAssertEqual(store.question.question?.id, "question-today")
        XCTAssertEqual(store.path, [])
        let remainingDestination = await pending.peek()
        XCTAssertNil(remainingDestination)
        XCTAssertEqual(
            store.globalErrorMessage,
            "この通知の質問は終了しました。今日の質問はホームから確認できます。"
        )
    }

    #if DEBUG
    func testPushDeepLinkFetchesUncachedAnswerAndOpensComments() async throws {
        let api = DemoAppAPI(startsAuthenticated: true)
        let store = AppStore(api: api, haptics: NoopHaptics())
        await store.restoreSession()
        store.home.feed?.answers = []

        let didOpen = await store.openPushAnswer(
            answerID: "demo-answer-family"
        )

        XCTAssertTrue(didOpen)
        XCTAssertEqual(
            store.path,
            [.home, .comments(answerID: "demo-answer-family")]
        )
        XCTAssertEqual(store.home.feed?.answers.first?.id, "demo-answer-family")
        XCTAssertFalse(
            store.commentThreads["demo-answer-family"]?.comments.isEmpty ?? true
        )
    }

    func testDemoFamilySetupRoutesThroughOrganizerPairingAndActivation() async throws {
        let api = DemoAppAPI(startsAuthenticated: false)
        let store = AppStore(api: api, haptics: NoopHaptics())

        await store.restoreSession()

        XCTAssertEqual(store.session, .signedOut)
        XCTAssertEqual(store.path, [.onboarding])

        store.familySetup.organizerName = "ゆうた"
        store.familySetup.familyName = "田中さんの家族"
        await store.createOrganizerFamily()

        guard case .signedIn(let organizer) = store.session else {
            return XCTFail("Expected the organizer to be authenticated")
        }
        XCTAssertEqual(organizer.displayName, "ゆうた")
        XCTAssertEqual(store.path, [.familySetup])
        XCTAssertEqual(store.familySetup.family?.name, "田中さんの家族")
        XCTAssertEqual(store.familySetup.family?.memberCount, 1)

        store.familySetup.managedMemberName = "まさこ"
        await store.createManagedMemberPairing()

        let pairing = try XCTUnwrap(store.familySetup.activePairing)
        XCTAssertEqual(pairing.code, "000001")
        XCTAssertEqual(pairing.member.displayName, "まさこ")
        XCTAssertEqual(store.path, [.familySetup, .pairingShare])
        XCTAssertEqual(store.familySetup.family?.memberCount, 2)
        XCTAssertEqual(store.familySetup.pairings.first?.id, pairing.id)

        await store.signOut()

        XCTAssertEqual(store.session, .signedOut)
        XCTAssertEqual(store.path, [.onboarding])

        store.preparePairingToken(pairing.token)
        await store.previewFamilyPairing()

        XCTAssertEqual(store.path.last, .pairingConfirmation)
        XCTAssertEqual(
            store.familySetup.pairingPreview?.member.displayName,
            "まさこ"
        )
        XCTAssertEqual(
            store.familySetup.pairingPreview?.family.name,
            "田中さんの家族"
        )

        await store.activateFamilyPairing()

        guard case .signedIn(let managedMember) = store.session else {
            return XCTFail("Expected the managed member to be authenticated")
        }
        XCTAssertEqual(managedMember.id, pairing.member.id)
        XCTAssertEqual(managedMember.displayName, "まさこ")
        XCTAssertEqual(store.path, [.pairingReady])
        XCTAssertNil(store.familySetup.pairingToken)
        XCTAssertEqual(store.familySetup.pairingCode, "")
        XCTAssertNil(store.familySetup.errorMessage)

        await store.finishFamilySetup()

        XCTAssertEqual(store.path, [.home])
        XCTAssertEqual(store.home.feed?.family?.name, "田中さんの家族")

        let didLeaveManagedFamily = await store.leaveFamily()
        XCTAssertTrue(didLeaveManagedFamily)
        XCTAssertEqual(store.session, .signedOut)
        XCTAssertEqual(store.path, [.onboarding])
        let managedSessionStillStored = await api.hasStoredSession()
        XCTAssertFalse(managedSessionStillStored)
    }

    func testDemoReissuesPairingForExistingMemberWithoutAddingAnother() async throws {
        let store = AppStore(
            api: DemoAppAPI(startsAuthenticated: false),
            haptics: NoopHaptics()
        )
        await store.restoreSession()
        store.familySetup.organizerName = "ゆうた"
        store.familySetup.familyName = "田中さんの家族"
        await store.createOrganizerFamily()
        store.familySetup.managedMemberName = "まさこ"
        await store.createManagedMemberPairing()

        let firstPairing = try XCTUnwrap(store.familySetup.activePairing)
        let managedMember = try XCTUnwrap(
            store.familySetup.family?.members.first(where: {
                $0.id == firstPairing.member.id
            })
        )
        store.path = [.familySetup]

        await store.createPairing(for: managedMember)

        XCTAssertEqual(store.familySetup.family?.memberCount, 2)
        XCTAssertEqual(store.familySetup.activePairing?.code, "000002")
        XCTAssertEqual(store.familySetup.pairings.count, 1)
        XCTAssertEqual(store.familySetup.pairings.first?.member.id, managedMember.id)
        XCTAssertEqual(store.path, [.familySetup, .pairingShare])
    }

    func testSignedInPairingLinkOpensRecoverableConfirmationRoute() async {
        let store = AppStore(
            api: DemoAppAPI(startsAuthenticated: true),
            haptics: NoopHaptics()
        )
        await store.restoreSession()

        store.preparePairingToken(String(repeating: "a", count: 48))

        XCTAssertEqual(store.path.last, .pairingConfirmation)
        XCTAssertEqual(
            store.familySetup.pairingToken,
            String(repeating: "a", count: 48)
        )
    }

    func testUpdatingDisplayNameRefreshesEveryCachedAuthor() async throws {
        let store = AppStore(
            api: DemoAppAPI(startsAuthenticated: true),
            haptics: NoopHaptics()
        )

        await store.restoreSession()
        await store.loadTodayQuestion()
        store.question.draft = "名前変更前の回答"
        await store.submitAnswer()
        await store.loadHistory()

        let familyAnswerID = try XCTUnwrap(
            store.home.feed?.answers.first(where: {
                $0.author.id != "demo-user"
            })?.id
        )
        await store.loadComments(answerID: familyAnswerID)
        await store.updateDisplayName("新しい名前")

        guard case .signedIn(let profile) = store.session else {
            return XCTFail("Expected an authenticated session")
        }
        XCTAssertEqual(profile.displayName, "新しい名前")
        XCTAssertEqual(
            store.home.feed?.family?.members.first(where: {
                $0.id == "demo-user"
            })?.displayName,
            "新しい名前"
        )
        XCTAssertTrue(
            store.home.feed?.answers
                .filter { $0.author.id == "demo-user" }
                .allSatisfy { $0.author.displayName == "新しい名前" }
                == true
        )
        XCTAssertEqual(
            store.home.feed?.myAnswer?.author.displayName,
            "新しい名前"
        )
        XCTAssertEqual(
            store.home.feed?.todayQuestion?.answer?.author.displayName,
            "新しい名前"
        )
        XCTAssertEqual(
            store.question.question?.answer?.author.displayName,
            "新しい名前"
        )
        XCTAssertTrue(
            store.history.answers
                .filter { $0.author.id == "demo-user" }
                .allSatisfy { $0.author.displayName == "新しい名前" }
        )
        XCTAssertTrue(
            store.commentThreads[familyAnswerID]?.comments
                .filter { $0.author.id == "demo-user" }
                .allSatisfy { $0.author.displayName == "新しい名前" }
                == true
        )
    }
    #endif
}

#if DEBUG
final class DemoAppAPITests: XCTestCase {
    func testLaunchModeRequiresExplicitOptIn() {
        XCTAssertEqual(
            DemoLaunchMode.current(
                environment: ["TSUTSUURA_DEMO_MODE": "authenticated"],
                arguments: []
            ),
            .authenticated
        )
        XCTAssertNil(
            DemoLaunchMode.current(environment: [:], arguments: [])
        )
    }

    func testSignedOutDemoCompletesOTPWithoutExternalProvider() async throws {
        let api = DemoAppAPI(startsAuthenticated: false)
        let initiallyAuthenticated = await api.hasStoredSession()

        XCTAssertFalse(initiallyAuthenticated)
        let challenge = try await api.requestOTP(phoneNumber: "09012345678")
        let session = try await api.verifyOTP(
            requestID: challenge.requestID,
            code: "123456"
        )
        let finallyAuthenticated = await api.hasStoredSession()

        XCTAssertEqual(session.user.id, "demo-user")
        XCTAssertTrue(finallyAuthenticated)
    }

    func testDemoOrganizerCreatesAndActivatesManagedMemberPairing() async throws {
        let api: any AppAPI = DemoAppAPI(startsAuthenticated: false)

        let organizerSession = try await api.createOrganizerFamily(
            organizerName: "ゆうた",
            familyName: "田中さんの家族"
        )
        XCTAssertEqual(organizerSession.user.displayName, "ゆうた")
        XCTAssertNil(organizerSession.user.phoneNumber)
        XCTAssertEqual(organizerSession.user.hasPhone, false)

        let managedMember = try await api.addManagedFamilyMember(
            displayName: "まさこ"
        )
        let pairing = try await api.createFamilyPairing(
            memberID: managedMember.id
        )

        XCTAssertEqual(pairing.code, "000001")
        XCTAssertEqual(pairing.status, .pending)
        XCTAssertEqual(pairing.member.id, managedMember.id)

        let codePreview = try await api.previewFamilyPairing(
            .code(pairing.code)
        )
        let tokenPreview = try await api.previewFamilyPairing(
            .token(pairing.token)
        )
        XCTAssertEqual(codePreview, tokenPreview)
        XCTAssertEqual(codePreview.family.name, "田中さんの家族")
        XCTAssertEqual(codePreview.member.displayName, "まさこ")

        let managedSession = try await api.activateFamilyPairing(
            .code(pairing.code)
        )
        XCTAssertEqual(managedSession.user.id, managedMember.id)
        XCTAssertEqual(managedSession.user.displayName, "まさこ")
        XCTAssertEqual(managedSession.user.family?.name, "田中さんの家族")

        let pairings = try await api.fetchFamilyPairings()
        XCTAssertEqual(
            pairings.first(where: { $0.id == pairing.id })?.status,
            .consumed
        )

        do {
            _ = try await api.activateFamilyPairing(.token(pairing.token))
            XCTFail("A consumed pairing must not be reusable")
        } catch {
            // Expected: pairing credentials are single-use.
        }
    }

    func testDemoPairedManagedSuccessorNeedsSeparateRecoverySetup() async throws {
        let api: any AppAPI = DemoAppAPI(startsAuthenticated: true)
        let managedMember = try await api.addManagedFamilyMember(
            displayName: "引き継ぎ候補"
        )
        let firstPairing = try await api.createFamilyPairing(
            memberID: managedMember.id
        )

        _ = try await api.activateFamilyPairing(.code(firstPairing.code))
        try await api.signOut()
        let ownerChallenge = try await api.requestOTP(
            phoneNumber: "090-1234-5678"
        )
        _ = try await api.verifyOTP(
            requestID: ownerChallenge.requestID,
            code: "123456"
        )

        do {
            _ = try await api.transferFamilyOwnership(to: managedMember.id)
            XCTFail("Pairing activation alone must not make an owner recoverable")
        } catch {}

        let recoveryPairing = try await api.createFamilyPairing(
            memberID: managedMember.id
        )
        try await api.signOut()
        _ = try await api.activateFamilyPairing(.token(recoveryPairing.token))
        let recoveryCode = try await api.createAccountRecoveryCode()
        try await api.signOut()
        let secondOwnerChallenge = try await api.requestOTP(
            phoneNumber: "090-1234-5678"
        )
        _ = try await api.verifyOTP(
            requestID: secondOwnerChallenge.requestID,
            code: "123456"
        )

        let transferred = try await api.transferFamilyOwnership(
            to: managedMember.id
        )
        let successor = try XCTUnwrap(
            transferred.members.first(where: { $0.id == managedMember.id })
        )
        XCTAssertEqual(successor.familyRole, .owner)
        XCTAssertEqual(successor.managed, false)

        try await api.signOut()
        let recoveredSuccessor = try await api.recoverAccount(
            code: recoveryCode.code
        )
        XCTAssertEqual(recoveredSuccessor.user.id, managedMember.id)
    }

    func testDemoPhoneEnrollmentMakesActivatedSuccessorEligible() async throws {
        let api: any AppAPI = DemoAppAPI(startsAuthenticated: true)
        let managedMember = try await api.addManagedFamilyMember(
            displayName: "電話登録する候補"
        )
        let pairing = try await api.createFamilyPairing(
            memberID: managedMember.id
        )
        _ = try await api.activateFamilyPairing(.code(pairing.code))
        let enrollment = try await api.requestPhoneEnrollment(
            phoneNumber: "080-1111-2222"
        )
        _ = try await api.verifyPhoneEnrollment(
            requestID: enrollment.requestID,
            code: "123456"
        )

        try await api.signOut()
        let ownerChallenge = try await api.requestOTP(
            phoneNumber: "090-1234-5678"
        )
        _ = try await api.verifyOTP(
            requestID: ownerChallenge.requestID,
            code: "123456"
        )
        let transferred = try await api.transferFamilyOwnership(
            to: managedMember.id
        )

        XCTAssertEqual(
            transferred.members.first(where: {
                $0.id == managedMember.id
            })?.familyRole,
            .owner
        )
    }

    func testDemoNameMutationsEnforceEmptyAndEightyCharacterBoundaries() async throws {
        let validName = String(repeating: "あ", count: 80)
        let oversizedName = String(repeating: "あ", count: 81)
        let validComposedName = String(repeating: "e\u{301}", count: 40)
        let oversizedComposedName = validComposedName + "e"
        let api: any AppAPI = DemoAppAPI(startsAuthenticated: true)

        let profile = try await api.updateProfile(displayName: validName)
        XCTAssertEqual(profile.displayName, validName)
        let composedProfile = try await api.updateProfile(
            displayName: validComposedName
        )
        XCTAssertEqual(composedProfile.displayName, validComposedName)
        await expectDemoInputRejection {
            _ = try await api.updateProfile(displayName: oversizedName)
        }
        await expectDemoInputRejection {
            _ = try await api.updateProfile(displayName: oversizedComposedName)
        }
        await expectDemoInputRejection {
            _ = try await api.updateProfile(displayName: " \n ")
        }

        let family = try await api.renameFamily(name: validName)
        XCTAssertEqual(family.name, validName)
        await expectDemoInputRejection {
            _ = try await api.renameFamily(name: oversizedName)
        }
        await expectDemoInputRejection {
            _ = try await api.renameFamily(name: " \t ")
        }

        let managedMember = try await api.addManagedFamilyMember(
            displayName: validName
        )
        XCTAssertEqual(managedMember.displayName, validName)
        await expectDemoInputRejection {
            _ = try await api.addManagedFamilyMember(
                displayName: oversizedName
            )
        }
        await expectDemoInputRejection {
            _ = try await api.addManagedFamilyMember(displayName: "   ")
        }

        let renamedMember = try await api.renameManagedFamilyMember(
            memberID: managedMember.id,
            displayName: validName
        )
        XCTAssertEqual(renamedMember.displayName, validName)
        await expectDemoInputRejection {
            _ = try await api.renameManagedFamilyMember(
                memberID: managedMember.id,
                displayName: oversizedName
            )
        }
        await expectDemoInputRejection {
            _ = try await api.renameManagedFamilyMember(
                memberID: managedMember.id,
                displayName: "\n"
            )
        }

        let organizerAPI: any AppAPI = DemoAppAPI(startsAuthenticated: false)
        let session = try await organizerAPI.createOrganizerFamily(
            organizerName: validName,
            familyName: validName
        )
        XCTAssertEqual(session.user.displayName, validName)
        XCTAssertEqual(session.user.family?.name, validName)

        for invalidOrganizerName in [oversizedName, "  "] {
            let candidateAPI: any AppAPI = DemoAppAPI(startsAuthenticated: false)
            await expectDemoInputRejection {
                _ = try await candidateAPI.createOrganizerFamily(
                    organizerName: invalidOrganizerName,
                    familyName: validName
                )
            }
        }
        for invalidFamilyName in [oversizedName, "\n\t"] {
            let candidateAPI: any AppAPI = DemoAppAPI(startsAuthenticated: false)
            await expectDemoInputRejection {
                _ = try await candidateAPI.createOrganizerFamily(
                    organizerName: validName,
                    familyName: invalidFamilyName
                )
            }
        }
    }

    func testAuthenticatedDemoSupportsPrimaryStateMutations() async throws {
        let api = DemoAppAPI(startsAuthenticated: true)
        let initialHome = try await api.fetchHome(cursor: nil)
        let answer = try XCTUnwrap(initialHome.answers.first)
        let initialComments = try await api.fetchComments(
            answerID: answer.id,
            cursor: nil
        )

        XCTAssertEqual(initialHome.family?.memberCount, 2)
        XCTAssertNil(initialHome.todayQuestion?.answer)
        XCTAssertFalse(initialComments.comments.isEmpty)

        let like = try await api.setLike(
            answerID: answer.id,
            isLiked: !answer.isLikedByMe
        )
        XCTAssertEqual(like.isLikedByMe, !answer.isLikedByMe)

        let updatedProfile = try await api.updateProfile(
            displayName: "デモの名前"
        )
        XCTAssertEqual(updatedProfile.displayName, "デモの名前")

        let question = try await api.fetchTodayQuestion()
        let submittedAnswer = try await api.submitAnswer(
            questionID: question.id,
            body: "デモからの回答"
        )
        let refreshedHome = try await api.fetchHome(cursor: nil)
        let refreshedHistory = try await api.fetchAnswerHistory(cursor: nil)

        XCTAssertEqual(submittedAnswer.body, "デモからの回答")
        do {
            _ = try await api.setLike(answerID: submittedAnswer.id, isLiked: true)
            XCTFail("A user must not be able to like their own answer")
        } catch {
            // Expected.
        }
        XCTAssertEqual(refreshedHome.myAnswer?.id, submittedAnswer.id)
        XCTAssertEqual(
            refreshedHistory.answers.first?.id,
            submittedAnswer.id
        )
    }

    func testDemoRoundTripsSubmittedAnswerMedia() async throws {
        let api: any AppAPI = DemoAppAPI(startsAuthenticated: true)
        let question = try await api.fetchTodayQuestion()
        let audioData = Data("demo-audio".utf8)
        let photoData = Data("demo-photo".utf8)
        let unsafePhotoFileName = "../\"\u{0001}" + String(
            repeating: "e\u{301}",
            count: 101
        )

        let answer = try await api.submitAnswer(
            questionID: question.id,
            submission: AnswerSubmission(
                body: "メディア付き",
                voiceRecording: AnswerMediaUpload(
                    data: audioData,
                    fileName: "voice.m4a",
                    mimeType: "audio/mp4",
                    durationMilliseconds: 800
                ),
                photos: [
                    AnswerMediaUpload(
                        data: photoData,
                        fileName: unsafePhotoFileName,
                        mimeType: "image/jpeg"
                    )
                ]
            )
        )

        XCTAssertEqual(answer.media.map(\.kind), [.audio, .photo])
        let audio = try XCTUnwrap(answer.media.first)
        let photo = try XCTUnwrap(answer.media.last)
        XCTAssertEqual(
            photo.fileName,
            AnswerMediaUpload.sanitizedFileName(unsafePhotoFileName)
        )
        let fetchedAudio = try await api.fetchAnswerMedia(audio)
        let fetchedPhoto = try await api.fetchAnswerMedia(photo)
        XCTAssertEqual(fetchedAudio.data, audioData)
        XCTAssertEqual(fetchedPhoto.data, photoData)
    }

    func testDemoCommentMutationsPersistAnswerCount() async throws {
        let api = DemoAppAPI(startsAuthenticated: true)
        let initialHome = try await api.fetchHome(cursor: nil)
        let answer = try XCTUnwrap(initialHome.answers.first)

        let comment = try await api.createComment(
            answerID: answer.id,
            body: "増えたコメント"
        )
        let homeAfterCreate = try await api.fetchHome(cursor: nil)
        XCTAssertEqual(
            homeAfterCreate.answers.first(where: { $0.id == answer.id })?
                .commentCount,
            answer.commentCount + 1
        )

        try await api.deleteComment(
            commentID: comment.id,
            answerID: answer.id
        )
        let homeAfterDelete = try await api.fetchHome(cursor: nil)
        XCTAssertEqual(
            homeAfterDelete.answers.first(where: { $0.id == answer.id })?
                .commentCount,
            answer.commentCount
        )
    }

    func testDemoPhoneEnrollmentAndOneTimeRecoveryLifecycle() async throws {
        let api: any AppAPI = DemoAppAPI(startsAuthenticated: true)

        let challenge = try await api.requestPhoneEnrollment(
            phoneNumber: "+819055512345"
        )
        let enrolledProfile = try await api.verifyPhoneEnrollment(
            requestID: challenge.requestID,
            code: "123456"
        )
        XCTAssertEqual(enrolledProfile.phoneNumber, "+819055512345")
        XCTAssertEqual(enrolledProfile.hasPhone, true)

        let recoveryCode = try await api.createAccountRecoveryCode()
        XCTAssertGreaterThan(recoveryCode.expiresAt, Date())
        XCTAssertGreaterThanOrEqual(recoveryCode.code.count, 40)
        try await api.signOut()
        let signedOut = try await api.hasStoredSession()
        XCTAssertFalse(signedOut)

        do {
            _ = try await api.recoverAccount(code: "not-the-code")
            XCTFail("An invalid recovery code must fail")
        } catch {}

        let recoveredSession = try await api.recoverAccount(
            code: recoveryCode.code
        )
        XCTAssertEqual(recoveredSession.user.id, "demo-user")
        let recovered = try await api.hasStoredSession()
        XCTAssertTrue(recovered)

        try await api.signOut()
        do {
            _ = try await api.recoverAccount(code: recoveryCode.code)
            XCTFail("A recovery code must be single-use")
        } catch {}
    }

    func testDemoFamilyLifecycleRenamesRemovesAndEnforcesOwnership() async throws {
        let api: any AppAPI = DemoAppAPI(startsAuthenticated: true)
        let initialFamily = try await api.fetchFamily()
        let managedMember = try XCTUnwrap(
            initialFamily.members.first(where: { $0.managed == true })
        )

        let renamedFamily = try await api.renameFamily(name: "新しい家族名")
        XCTAssertEqual(renamedFamily.name, "新しい家族名")
        let renamedMember = try await api.renameManagedFamilyMember(
            memberID: managedMember.id,
            displayName: "新しい家族"
        )
        XCTAssertEqual(renamedMember.displayName, "新しい家族")

        let refreshedHome = try await api.fetchHome(cursor: nil)
        XCTAssertEqual(refreshedHome.family?.name, "新しい家族名")
        XCTAssertTrue(
            refreshedHome.answers
                .filter { $0.author.id == managedMember.id }
                .allSatisfy { $0.author.displayName == "新しい家族" }
        )

        do {
            _ = try await api.leaveFamily()
            XCTFail("The owner must transfer ownership before leaving")
        } catch {}

        try await api.removeManagedFamilyMember(memberID: managedMember.id)
        let familyAfterRemoval = try await api.fetchFamily()
        XCTAssertEqual(familyAfterRemoval.memberCount, 1)
        XCTAssertFalse(
            familyAfterRemoval.members.contains(where: {
                $0.id == managedMember.id
            })
        )
        let homeAfterRemoval = try await api.fetchHome(cursor: nil)
        XCTAssertFalse(
            homeAfterRemoval.answers.contains(where: {
                $0.author.id == managedMember.id
            })
        )
    }

    @MainActor
    func testConcreteDemoDispatchSupportsOwnershipPromotionAndLeave() async throws {
        let api = DemoAppAPI(startsAuthenticated: true)
        let store = AppStore(api: api, haptics: NoopHaptics())
        await store.restoreSession()
        await store.loadFamilySetup()

        let originalFamilyID = try XCTUnwrap(store.familySetup.family?.id)
        var originalPreferences = try await api.fetchNotificationPreferences()
        originalPreferences.commentsEnabled = false
        _ = try await api.updateNotificationPreferences(originalPreferences)
        let successor = try XCTUnwrap(
            store.familySetup.family?.members.first(where: {
                $0.id != "demo-user" && $0.managed == true
            })
        )

        let didTransfer = await store.transferFamilyOwnership(to: successor.id)
        XCTAssertTrue(didTransfer)
        guard case .signedIn(let formerOwner) = store.session else {
            return XCTFail("Expected the former owner to remain signed in")
        }
        XCTAssertEqual(formerOwner.familyRole, .member)

        let didLeave = await store.leaveFamily()
        XCTAssertTrue(didLeave)
        guard case .signedIn(let replacementOwner) = store.session else {
            return XCTFail("A regular family leave must preserve authentication")
        }
        XCTAssertEqual(store.path, [.home])
        XCTAssertEqual(replacementOwner.familyRole, .owner)
        XCTAssertEqual(replacementOwner.managed, false)
        XCTAssertNotEqual(replacementOwner.family?.id, originalFamilyID)
        XCTAssertEqual(replacementOwner.family?.name, "わたしの家族")
        XCTAssertEqual(replacementOwner.family?.memberCount, 1)
        XCTAssertEqual(store.home.feed?.answers, [])
        XCTAssertEqual(store.history.answers, [])
        let replacementPreferences = try await api.fetchNotificationPreferences()
        XCTAssertEqual(
            replacementPreferences.familyID,
            replacementOwner.family?.id
        )
        XCTAssertTrue(replacementPreferences.commentsEnabled)
    }

    func testDemoAnswerEditMediaDeleteAndDeleteLifecycle() async throws {
        let api: any AppAPI = DemoAppAPI(startsAuthenticated: true)
        let question = try await api.fetchTodayQuestion()
        let answer = try await api.submitAnswer(
            questionID: question.id,
            submission: AnswerSubmission(
                body: "元の回答",
                photos: [
                    AnswerMediaUpload(
                        data: Data([0x01, 0x02]),
                        fileName: "memory.jpg",
                        mimeType: "image/jpeg"
                    )
                ]
            )
        )
        let photo = try XCTUnwrap(answer.media.first)

        let updated = try await api.updateAnswer(
            answerID: answer.id,
            submission: AnswerSubmission(body: "編集した回答")
        )
        XCTAssertEqual(updated.body, "編集した回答")
        XCTAssertEqual(updated.media, answer.media)

        let withoutPhoto = try await api.deleteAnswerMedia(
            answerID: answer.id,
            mediaID: photo.id
        )
        XCTAssertTrue(withoutPhoto.media.isEmpty)
        XCTAssertEqual(withoutPhoto.body, "編集した回答")

        try await api.deleteAnswer(answerID: answer.id)
        let home = try await api.fetchHome(cursor: nil)
        let history = try await api.fetchAnswerHistory(
            query: HistoryQuery(scope: .family),
            cursor: nil
        )
        XCTAssertNil(home.myAnswer)
        XCTAssertFalse(home.answers.contains(where: { $0.id == answer.id }))
        XCTAssertFalse(history.answers.contains(where: { $0.id == answer.id }))

        let someoneElsesAnswer = try XCTUnwrap(home.answers.first)
        do {
            try await api.deleteAnswer(answerID: someoneElsesAnswer.id)
            XCTFail("Another family member's answer must not be deletable")
        } catch {}
    }

    func testDemoCommentReplyEditReportAndDeleteLifecycle() async throws {
        let api: any AppAPI = DemoAppAPI(startsAuthenticated: true)
        let home = try await api.fetchHome(cursor: nil)
        let answer = try XCTUnwrap(
            home.answers.first(where: { $0.author.id != "demo-user" })
        )
        let initialPage = try await api.fetchComments(
            answerID: answer.id,
            cursor: nil
        )
        let familyComment = try XCTUnwrap(
            initialPage.comments.first(where: { $0.author.id != "demo-user" })
        )

        let ownComment = try await api.createComment(
            answerID: answer.id,
            body: "自分のコメント"
        )
        let editedComment = try await api.updateComment(
            commentID: ownComment.id,
            body: "編集したコメント"
        )
        XCTAssertEqual(editedComment.body, "編集したコメント")
        XCTAssertNotNil(editedComment.updatedAt)

        let reply = try await api.replyToComment(
            answerID: answer.id,
            parentCommentID: familyComment.id,
            body: "返信"
        )
        XCTAssertEqual(reply.parentCommentID, familyComment.id)

        let report = try await api.reportComment(
            commentID: familyComment.id,
            reason: .inappropriate,
            details: "確認してください"
        )
        XCTAssertEqual(report.commentID, familyComment.id)
        XCTAssertEqual(report.status, "pending")

        do {
            _ = try await api.updateComment(
                commentID: familyComment.id,
                body: "変更"
            )
            XCTFail("Another member's comment must not be editable")
        } catch {}
        do {
            _ = try await api.reportComment(
                commentID: ownComment.id,
                reason: .spam,
                details: nil
            )
            XCTFail("A user must not report their own comment")
        } catch {}

        try await api.deleteComment(
            commentID: ownComment.id,
            answerID: answer.id
        )
        try await api.deleteComment(
            commentID: reply.id,
            answerID: answer.id
        )
        let finalPage = try await api.fetchComments(
            answerID: answer.id,
            cursor: nil
        )
        XCTAssertFalse(finalPage.comments.contains(where: { $0.id == ownComment.id }))
        XCTAssertFalse(finalPage.comments.contains(where: { $0.id == reply.id }))
        let finalHome = try await api.fetchHome(cursor: nil)
        XCTAssertEqual(
            finalHome.answers.first(where: { $0.id == answer.id })?.commentCount,
            answer.commentCount
        )
    }

    func testDemoCommentDeleteEnforcesCommentOwnership() async throws {
        let api: any AppAPI = DemoAppAPI(startsAuthenticated: true)
        let home = try await api.fetchHome(cursor: nil)
        let answer = try XCTUnwrap(
            home.answers.first(where: { $0.author.id != "demo-user" })
        )
        let page = try await api.fetchComments(answerID: answer.id, cursor: nil)
        let familyComment = try XCTUnwrap(
            page.comments.first(where: { $0.author.id != "demo-user" })
        )

        do {
            try await api.deleteComment(
                commentID: familyComment.id,
                answerID: answer.id
            )
            XCTFail("Another member's comment must not be deletable")
        } catch {}

        let unchangedPage = try await api.fetchComments(
            answerID: answer.id,
            cursor: nil
        )
        XCTAssertTrue(
            unchangedPage.comments.contains(where: { $0.id == familyComment.id })
        )
    }

    func testConcreteDemoDispatchSupportsPreferencesHistoryExportAndDeletion() async throws {
        let api = DemoAppAPI(startsAuthenticated: true)
        var preferences = try await api.fetchNotificationPreferences()
        preferences.enabled = false
        preferences.commentsEnabled = false
        preferences.quietStart = "21:30"
        preferences.quietEnd = "07:00"
        preferences.timeZoneIdentifier = "Asia/Tokyo"
        let savedPreferences = try await api.updateNotificationPreferences(
            preferences
        )
        XCTAssertEqual(savedPreferences, preferences)
        let fetchedPreferences = try await api.fetchNotificationPreferences()
        XCTAssertEqual(fetchedPreferences, preferences)

        let firstPage = try await api.fetchAnswerHistory(
            query: HistoryQuery(scope: .family, limit: 1),
            cursor: nil
        )
        XCTAssertEqual(firstPage.answers.count, 1)
        let cursor = try XCTUnwrap(firstPage.nextCursor)
        let secondPage = try await api.fetchAnswerHistory(
            query: HistoryQuery(scope: .family, limit: 1),
            cursor: cursor
        )
        XCTAssertEqual(secondPage.answers.count, 1)
        XCTAssertNotEqual(firstPage.answers.first?.id, secondPage.answers.first?.id)

        let mine = try await api.fetchAnswerHistory(
            query: HistoryQuery(scope: .mine),
            cursor: nil
        )
        XCTAssertTrue(mine.answers.allSatisfy { $0.author.id == "demo-user" })
        let searched = try await api.fetchAnswerHistory(
            query: HistoryQuery(scope: .family, searchText: "夕飯"),
            cursor: nil
        )
        XCTAssertEqual(searched.answers.count, 1)
        XCTAssertTrue(searched.answers[0].body.contains("夕飯"))
        let searchedByAuthor = try await api.fetchAnswerHistory(
            query: HistoryQuery(scope: .family, searchText: "あおい"),
            cursor: nil
        )
        XCTAssertEqual(searchedByAuthor.answers.map(\.id), ["demo-answer-family"])
        let dated = try await api.fetchAnswerHistory(
            query: HistoryQuery(
                scope: .family,
                startDate: "2026-07-27",
                endDate: "2026-07-27"
            ),
            cursor: nil
        )
        XCTAssertTrue(dated.answers.allSatisfy { $0.answerDate == "2026-07-27" })

        let export = try await api.exportAccount()
        XCTAssertEqual(export.user.id, "demo-user")
        XCTAssertEqual(export.notificationPreferences, preferences)
        XCTAssertFalse(export.answers.isEmpty)
        XCTAssertFalse(export.comments.isEmpty)

        try await api.deleteAccount()
        let hasSession = try await api.hasStoredSession()
        XCTAssertFalse(hasSession)
        do {
            _ = try await api.fetchMe()
            XCTFail("A deleted account must no longer be authenticated")
        } catch {}
    }

    private func expectDemoInputRejection(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail(
                "Expected invalid Demo name input to be rejected",
                file: file,
                line: line
            )
        } catch {
            // Rejection is the contract; the private Demo error is intentionally
            // not exposed through AppAPI.
        }
    }
}
#endif

private func familyPayloadForLeave(id: String) -> Data {
    Data(
        """
        {"data":{"id":"\(id)","name":"家族","memberCount":2,"members":[
          {"id":"user-1","displayName":"かえで","avatarUrl":null,"hasPhone":true,"managed":false,"role":"member"},
          {"id":"user-2","displayName":"あおい","avatarUrl":null,"hasPhone":false,"managed":true,"role":"owner"}
        ]}}
        """.utf8
    )
}

private enum ScriptedHTTPResult: Sendable {
    case response(
        statusCode: Int,
        data: Data,
        headers: [String: String] = ["Content-Type": "application/json"]
    )
    case urlError(URLError.Code)
}

private actor ScriptedHTTPTransport: HTTPTransport {
    private var remainingSteps: [ScriptedHTTPResult]
    private var requests: [URLRequest] = []

    init(steps: [ScriptedHTTPResult]) {
        remainingSteps = steps
    }

    var requestCount: Int { requests.count }
    var methods: [String] { requests.compactMap(\.httpMethod) }
    var paths: [String] { requests.compactMap { $0.url?.path } }
    var idempotencyKeys: [String?] {
        requests.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }
    }
    var authorizationHeaders: [String?] {
        requests.map { $0.value(forHTTPHeaderField: "Authorization") }
    }
    var bodies: [Data?] { requests.map(\.httpBody) }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !remainingSteps.isEmpty else {
            throw URLError(.unknown)
        }
        let step = remainingSteps.removeFirst()
        switch step {
        case .urlError(let code):
            throw URLError(code)
        case .response(let statusCode, let data, let headers):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (data, response)
        }
    }
}

private actor RecordingHTTPTransport: HTTPTransport {
    private(set) var lastRequest: URLRequest?
    private let statusCode: Int
    private let responseData: Data
    private let responseHeaders: [String: String]

    init(
        statusCode: Int,
        responseData: Data,
        responseHeaders: [String: String] = ["Content-Type": "application/json"]
    ) {
        self.statusCode = statusCode
        self.responseData = responseData
        self.responseHeaders = responseHeaders
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: responseHeaders
        )!
        return (responseData, response)
    }
}

private actor StubAppAPI: AppAPI {
    private let storedSession: Bool
    private let throwsOnSessionRead: Bool
    private let otpChallenge: OTPChallenge
    private var fetchedUsers: [UserProfile]
    private var homeFeeds: [HomeFeed]
    private var fetchMeFailuresRemaining: Int
    private let signOutFails: Bool
    private let fetchedAnswer: Answer?
    private let submittedAnswer: Answer?
    private let updatedAnswer: Answer?
    private let answerIsMissing: Bool
    private let todayQuestionIsMissing: Bool
    private let fetchedTodayQuestion: Question?
    private let commentsAreMissing: Bool
    private var commentPages: [CommentPage]
    private var commentFailuresRemaining: Int
    private var commentCursors: [String?] = []

    init(
        storedSession: Bool,
        throwsOnSessionRead: Bool = false,
        fetchedUser: UserProfile? = nil,
        fetchedUsers: [UserProfile]? = nil,
        homeFeeds: [HomeFeed] = [],
        fetchMeFailuresRemaining: Int = 0,
        signOutFails: Bool = false,
        fetchedAnswer: Answer? = nil,
        submittedAnswer: Answer? = nil,
        updatedAnswer: Answer? = nil,
        answerIsMissing: Bool = false,
        todayQuestionIsMissing: Bool = false,
        fetchedTodayQuestion: Question? = nil,
        commentsAreMissing: Bool = false,
        commentPages: [CommentPage] = [],
        commentFailuresRemaining: Int = 0,
        otpChallenge: OTPChallenge = OTPChallenge(
            requestID: "request",
            expiresIn: 300
        )
    ) {
        self.storedSession = storedSession
        self.throwsOnSessionRead = throwsOnSessionRead
        self.fetchedUsers = fetchedUsers ?? fetchedUser.map { [$0] } ?? []
        self.homeFeeds = homeFeeds
        self.fetchMeFailuresRemaining = fetchMeFailuresRemaining
        self.signOutFails = signOutFails
        self.fetchedAnswer = fetchedAnswer
        self.submittedAnswer = submittedAnswer
        self.updatedAnswer = updatedAnswer
        self.answerIsMissing = answerIsMissing
        self.todayQuestionIsMissing = todayQuestionIsMissing
        self.fetchedTodayQuestion = fetchedTodayQuestion
        self.commentsAreMissing = commentsAreMissing
        self.commentPages = commentPages
        self.commentFailuresRemaining = commentFailuresRemaining
        self.otpChallenge = otpChallenge
    }

    func hasStoredSession() throws -> Bool {
        if throwsOnSessionRead {
            throw StubError.unavailable
        }
        return storedSession
    }

    func requestOTP(phoneNumber: String) -> OTPChallenge {
        otpChallenge
    }

    func requestPhoneEnrollment(phoneNumber: String) -> OTPChallenge {
        otpChallenge
    }

    func verifyOTP(requestID: String, code: String) throws -> AuthSession {
        throw StubError.unimplemented
    }

    func verifyPhoneEnrollment(
        requestID: String,
        code: String
    ) throws -> UserProfile {
        throw StubError.unimplemented
    }

    func fetchMe() throws -> UserProfile {
        if fetchMeFailuresRemaining > 0 {
            fetchMeFailuresRemaining -= 1
            throw StubError.unavailable
        }
        guard let fetchedUser = fetchedUsers.first else {
            throw StubError.unimplemented
        }
        if fetchedUsers.count > 1 {
            fetchedUsers.removeFirst()
        }
        return fetchedUser
    }

    func updateProfile(displayName: String) throws -> UserProfile {
        throw StubError.unimplemented
    }

    func fetchFamily() throws -> FamilySummary {
        throw StubError.unimplemented
    }

    func fetchHome(cursor: String?) throws -> HomeFeed {
        guard let feed = homeFeeds.first else {
            throw StubError.unimplemented
        }
        if homeFeeds.count > 1 {
            homeFeeds.removeFirst()
        }
        return feed
    }

    func fetchTodayQuestion() throws -> Question {
        if todayQuestionIsMissing {
            throw APIClientError.server(statusCode: 404, payload: nil)
        }
        if let fetchedTodayQuestion {
            return fetchedTodayQuestion
        }
        throw StubError.unimplemented
    }

    func fetchAnswer(answerID: String) throws -> Answer {
        if answerIsMissing {
            throw APIClientError.server(statusCode: 404, payload: nil)
        }
        guard let fetchedAnswer, fetchedAnswer.id == answerID else {
            throw StubError.unimplemented
        }
        return fetchedAnswer
    }

    func submitAnswer(questionID: String, body: String) throws -> Answer {
        guard let submittedAnswer,
              submittedAnswer.questionID == questionID else {
            throw StubError.unimplemented
        }
        return submittedAnswer
    }

    func updateAnswer(
        answerID: String,
        submission: AnswerSubmission
    ) throws -> Answer {
        guard let updatedAnswer, updatedAnswer.id == answerID else {
            throw StubError.unimplemented
        }
        return updatedAnswer
    }

    func fetchAnswerHistory(cursor: String?) throws -> AnswerPage {
        throw StubError.unimplemented
    }

    func setLike(answerID: String, isLiked: Bool) throws -> LikeState {
        throw StubError.unimplemented
    }

    func fetchComments(
        answerID: String,
        cursor: String?
    ) throws -> CommentPage {
        commentCursors.append(cursor)
        if commentsAreMissing {
            throw APIClientError.server(statusCode: 404, payload: nil)
        }
        if commentFailuresRemaining > 0 {
            commentFailuresRemaining -= 1
            throw StubError.unavailable
        }
        guard let page = commentPages.first else {
            throw StubError.unimplemented
        }
        commentPages.removeFirst()
        return page
    }

    func observedCommentCursors() -> [String?] {
        commentCursors
    }

    func createComment(answerID: String, body: String) throws -> tsutsuura.Comment {
        throw StubError.unimplemented
    }

    func deleteComment(commentID: String, answerID: String) throws {
        throw StubError.unimplemented
    }

    func registerPushToken(
        _ token: String,
        environment: PushEnvironment
    ) throws {
        throw StubError.unimplemented
    }

    func unregisterPushToken(tokenHash: String) throws {
        throw StubError.unimplemented
    }

    func signOut() throws {
        if signOutFails {
            throw StubError.unavailable
        }
    }
}

private enum StubError: Error {
    case unavailable
    case unimplemented
}
