import Foundation
import XCTest
@testable import iChart

final class IChartComplimentaryOfferPolicyTests: XCTestCase {
    private let monthlyID = IChartStoreKitProductCatalog.proMonthlyProductID
    private let annualID = IChartStoreKitProductCatalog.proAnnualProductID

    func testIntroductoryOfferRequiresAppleEligibilityAndExactFreeMonthMetadata() throws {
        let response = server(decision: .introductory, productID: monthlyID, activation: .immediate)
        let offer = try XCTUnwrap(IChartComplimentaryOfferPolicy.availableOffer(
            response: response,
            metadata: metadata(productID: monthlyID, kind: .introductory),
            appleIntroEligible: true
        ))

        XCTAssertEqual(offer.offerDisplayPrice, "$0.00")
        XCTAssertEqual(offer.renewalDisplayPrice, "$7.99")
        XCTAssertEqual(offer.renewalPeriodDescription, "month")
        XCTAssertNil(IChartComplimentaryOfferPolicy.availableOffer(
            response: response,
            metadata: metadata(productID: monthlyID, kind: .introductory),
            appleIntroEligible: false
        ))
    }

    func testFreeActionRejectsNonfreeWrongModeWrongPeriodAndWrongCount() {
        let response = server(decision: .introductory, productID: monthlyID, activation: .immediate)
        XCTAssertNil(available(response, metadata(productID: monthlyID, kind: .introductory, price: 1)))
        XCTAssertNil(available(response, metadata(productID: monthlyID, kind: .introductory, mode: .other)))
        XCTAssertNil(available(response, metadata(productID: monthlyID, kind: .introductory, period: .weeks(4))))
        XCTAssertNil(available(response, metadata(productID: monthlyID, kind: .introductory, periodCount: 2)))
    }

    func testPromotionalAndScheduledOffersRequireExactFetchedOfferAndProduct() throws {
        let promotional = server(
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate
        )
        XCTAssertNotNil(available(
            promotional,
            metadata(productID: monthlyID, offerID: "free-month", kind: .promotional)
        ))
        XCTAssertNil(available(
            promotional,
            metadata(productID: monthlyID, offerID: "another-offer", kind: .promotional)
        ))

        let scheduled = server(
            decision: .scheduledPromotional,
            productID: annualID,
            offerID: "free-month",
            activation: .nextBillingEvent
        )
        XCTAssertNotNil(available(
            scheduled,
            metadata(
                productID: annualID,
                offerID: "free-month",
                kind: .promotional,
                renewalPeriod: .years(1)
            )
        ))
        XCTAssertNotNil(available(
            server(
                decision: .scheduledPromotional,
                productID: monthlyID,
                offerID: "free-month",
                activation: .nextBillingEvent
            ),
            metadata(productID: monthlyID, offerID: "free-month", kind: .promotional)
        ))
    }

    func testStatusNeverAcceptsSignatureOrUnavailableCampaign() {
        let response = server(
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate,
            signature: signature()
        )
        XCTAssertNil(available(
            response,
            metadata(productID: monthlyID, offerID: "free-month", kind: .promotional)
        ))

        let disabled = server(
            enabled: false,
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate
        )
        XCTAssertNil(available(
            disabled,
            metadata(productID: monthlyID, offerID: "free-month", kind: .promotional)
        ))
    }

    func testPreparedStatusRequiresAttemptForFreshRetry() {
        let missingAttempt = server(
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate,
            state: .prepared
        )
        XCTAssertNil(available(
            missingAttempt,
            metadata(productID: monthlyID, offerID: "free-month", kind: .promotional)
        ))

        let priorAttempt = server(
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate,
            state: .prepared,
            attemptID: UUID().uuidString
        )
        XCTAssertNotNil(available(
            priorAttempt,
            metadata(productID: monthlyID, offerID: "free-month", kind: .promotional)
        ))
    }

    func testPreparedAuthorizationIsBoundToDisplayedOfferAndFreshAttempt() throws {
        let attemptID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let displayed = try XCTUnwrap(available(
            server(
                decision: .promotional,
                productID: monthlyID,
                offerID: "free-month",
                activation: .immediate
            ),
            metadata(productID: monthlyID, offerID: "free-month", kind: .promotional)
        ))
        let prepared = server(
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate,
            state: .prepared,
            signature: signature(),
            attemptID: attemptID.uuidString.lowercased()
        )

        let authorization = try XCTUnwrap(IChartComplimentaryOfferPolicy.preparedAuthorization(
            response: prepared,
            displayedOffer: displayed,
            attemptID: attemptID
        ))
        XCTAssertEqual(authorization.attemptID, attemptID)
        XCTAssertNotNil(authorization.signature)
        XCTAssertNil(IChartComplimentaryOfferPolicy.preparedAuthorization(
            response: prepared,
            displayedOffer: displayed,
            attemptID: UUID()
        ))
    }

    func testPreparedAuthorizationRejectsMalformedLegacySignature() throws {
        let attemptID = UUID()
        let displayed = try XCTUnwrap(available(
            server(
                decision: .promotional,
                productID: monthlyID,
                offerID: "free-month",
                activation: .immediate
            ),
            metadata(productID: monthlyID, offerID: "free-month", kind: .promotional)
        ))

        for malformed in [
            IChartComplimentaryOfferServerSignature(keyID: "", nonce: UUID().uuidString, signature: "AQID", timestamp: 1),
            IChartComplimentaryOfferServerSignature(keyID: "key", nonce: "not-a-uuid", signature: derSignature(), timestamp: 1),
            IChartComplimentaryOfferServerSignature(keyID: "key", nonce: UUID().uuidString, signature: "%%%", timestamp: 1),
            IChartComplimentaryOfferServerSignature(keyID: "key", nonce: UUID().uuidString, signature: derSignature(), timestamp: 0)
        ] {
            XCTAssertNil(IChartComplimentaryOfferPolicy.preparedAuthorization(
                response: server(
                    decision: .promotional,
                    productID: monthlyID,
                    offerID: "free-month",
                    activation: .immediate,
                    state: .prepared,
                    signature: malformed,
                    attemptID: attemptID.uuidString
                ),
                displayedOffer: displayed,
                attemptID: attemptID
            ))
        }
    }

    func testConfirmationAndPersistedStatusRequireBoundDatesAndState() throws {
        let attemptID = UUID()
        let offer = try XCTUnwrap(available(
            server(
                decision: .scheduledPromotional,
                productID: annualID,
                offerID: "free-month",
                activation: .nextBillingEvent
            ),
            metadata(
                productID: annualID,
                offerID: "free-month",
                kind: .promotional,
                renewalPeriod: .years(1)
            )
        ))
        let confirmed = server(
            decision: .scheduledPromotional,
            productID: annualID,
            offerID: "free-month",
            activation: .nextBillingEvent,
            state: .scheduled,
            attemptID: attemptID.uuidString,
            accessStartsAt: "2027-01-01T00:00:00Z",
            estimatedAccessEndsAt: "2027-02-01T00:00:00Z",
            accessEndsAtIsEstimated: true
        )

        XCTAssertTrue(IChartComplimentaryOfferPolicy.matchesConfirmedCampaign(
            confirmed,
            offer: offer,
            attemptID: attemptID
        ))
        XCTAssertEqual(IChartComplimentaryOfferPolicy.confirmedStatus(response: confirmed)?.state, .scheduled)

        let reversedDates = server(
            decision: .scheduledPromotional,
            productID: annualID,
            offerID: "free-month",
            activation: .nextBillingEvent,
            state: .scheduled,
            attemptID: attemptID.uuidString,
            accessStartsAt: "2027-02-01T00:00:00Z",
            estimatedAccessEndsAt: "2027-01-01T00:00:00Z",
            accessEndsAtIsEstimated: true
        )
        XCTAssertFalse(IChartComplimentaryOfferPolicy.matchesConfirmedCampaign(
            reversedDates,
            offer: offer,
            attemptID: attemptID
        ))
        XCTAssertNil(IChartComplimentaryOfferPolicy.confirmedStatus(response: reversedDates))
    }

    func testRequestEncodesFreshAttemptAndPreviousAttemptOnlyWhenProvided() throws {
        let attemptID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let previousID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let prepare = IChartComplimentaryOfferServerRequest(
            action: .prepare,
            productID: monthlyID,
            signedTransactionInfo: "signed",
            attemptID: attemptID,
            previousAttemptID: previousID
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(prepare)
        ) as? [String: Any])
        XCTAssertEqual(object["attemptID"] as? String, attemptID.uuidString.lowercased())
        XCTAssertEqual(object["previousAttemptID"] as? String, previousID.uuidString.lowercased())

        let status = IChartComplimentaryOfferServerRequest(action: .status, productID: monthlyID)
        let statusObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(status)
        ) as? [String: Any])
        XCTAssertNil(statusObject["attemptID"])
        XCTAssertNil(statusObject["previousAttemptID"])
    }

    func testPreparedStatusCanRecoverConfirmationWithoutReusingSignature() throws {
        let attemptID = UUID()
        let preparedStatus = server(
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate,
            state: .prepared,
            attemptID: attemptID.uuidString
        )
        XCTAssertEqual(
            IChartComplimentaryOfferPolicy.recoverablePreparedAttempt(
                response: preparedStatus,
                productID: monthlyID
            ),
            attemptID
        )

        let confirmed = server(
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate,
            state: .redeemed,
            attemptID: attemptID.uuidString,
            accessStartsAt: "2026-10-08T12:00:00Z",
            accessEndsAt: "2026-11-08T12:00:00Z"
        )
        XCTAssertTrue(IChartComplimentaryOfferPolicy.matchesRecoveredConfirmation(
            confirmed,
            prepared: preparedStatus,
            attemptID: attemptID
        ))
    }

    func testScheduledPreparationRecoversCompletedBillingForBothProducts() throws {
        for productID in [monthlyID, annualID] {
            let attemptID = UUID()
            let prepared = server(
                decision: .scheduledPromotional, productID: productID,
                offerID: "free-month", activation: .nextBillingEvent,
                state: .prepared, attemptID: attemptID.uuidString
            )
            let stillScheduled = server(
                decision: .scheduledPromotional, productID: productID,
                offerID: "free-month", activation: .nextBillingEvent,
                state: .scheduled, attemptID: attemptID.uuidString,
                accessStartsAt: "2026-10-10T12:00:00Z",
                estimatedAccessEndsAt: "2026-11-10T12:00:00Z",
                accessEndsAtIsEstimated: true
            )
            XCTAssertTrue(IChartComplimentaryOfferPolicy.matchesRecoveredConfirmation(
                stillScheduled, prepared: prepared, attemptID: attemptID
            ))
            for (start, end) in [
                ("2026-10-08T12:00:00Z", "2026-11-08T12:00:00Z"),
                ("2026-08-08T12:00:00Z", "2026-09-08T12:00:00Z")
            ] {
                let completed = server(
                    decision: .scheduledPromotional, productID: productID,
                    offerID: "free-month", activation: .nextBillingEvent,
                    state: .redeemed, attemptID: attemptID.uuidString,
                    accessStartsAt: start, accessEndsAt: end
                )
                XCTAssertTrue(IChartComplimentaryOfferPolicy.matchesRecoveredConfirmation(
                    completed, prepared: prepared, attemptID: attemptID
                ))
                // Confirmation of an ended gift is not an entitlement grant.
                XCTAssertEqual(IChartComplimentaryOfferPolicy.confirmedStatus(response: completed)?.state, .redeemed)
            }
        }
    }

    func testBillingBoundaryRecoveryRetainsBindingAndRejectsEstimatedCompletion() throws {
        let attemptID = UUID()
        let prepared = server(
            decision: .scheduledPromotional, productID: monthlyID,
            offerID: "free-month", activation: .nextBillingEvent,
            state: .prepared, attemptID: attemptID.uuidString
        )
        let completed = server(
            decision: .scheduledPromotional, productID: monthlyID,
            offerID: "free-month", activation: .nextBillingEvent,
            state: .redeemed, attemptID: attemptID.uuidString,
            accessStartsAt: "2026-10-08T12:00:00Z", accessEndsAt: "2026-11-08T12:00:00Z"
        )
        let original = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(completed)
        ) as? [String: Any])
        let changes: [[String: Any]] = [
            ["schemaVersion": 2], ["enabled": false], ["recoveryOnly": true],
            ["campaignID": "another-campaign"], ["productID": annualID],
            ["decision": "promotional"], ["activation": "immediate"],
            ["offerID": "another-offer"], ["attemptID": UUID().uuidString],
            ["attemptID": "invalid"], ["serverTime": "invalid"],
            ["state": "available"], ["state": "prepared"], ["state": "unavailable"],
            ["state": "scheduled"], ["accessStartsAt": NSNull()],
            ["accessEndsAt": NSNull()], ["accessEndsAt": "invalid"],
            ["accessEndsAt": "2026-10-08T12:00:00Z"],
            ["accessEndsAt": "2026-10-07T12:00:00Z"],
            ["accessEndsAtIsEstimated": true],
            ["estimatedAccessEndsAt": "2026-11-08T12:00:00Z"],
            ["signature": ["keyID": "apple-key", "nonce": UUID().uuidString,
                           "signature": derSignature(), "timestamp": 1_800_000_000]]
        ]
        for change in changes {
            let object = original.merging(change) { _, replacement in replacement }
            let rejected = try JSONDecoder().decode(IChartComplimentaryOfferServerResponse.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertFalse(IChartComplimentaryOfferPolicy.matchesRecoveredConfirmation(
                rejected, prepared: prepared, attemptID: attemptID
            ), "Unexpected acceptance: \(change.keys.sorted())")
        }
        XCTAssertFalse(IChartComplimentaryOfferPolicy.matchesRecoveredConfirmation(
            completed, prepared: prepared, attemptID: UUID()
        ))
    }

    func testPreparationDeadlineBlocksFreshOfferButNotPreparedRecovery() throws {
        let blockedAvailable = server(
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate,
            canPrepare: false
        )
        XCTAssertNil(available(
            blockedAvailable,
            metadata(productID: monthlyID, offerID: "free-month", kind: .promotional)
        ))

        let attemptID = UUID()
        let previouslyPrepared = server(
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate,
            state: .prepared,
            attemptID: attemptID.uuidString,
            canPrepare: false
        )
        XCTAssertNil(available(
            previouslyPrepared,
            metadata(productID: monthlyID, offerID: "free-month", kind: .promotional)
        ))
        XCTAssertEqual(
            IChartComplimentaryOfferPolicy.recoverablePreparedAttempt(
                response: previouslyPrepared,
                productID: monthlyID
            ),
            attemptID
        )

        let introductoryOffer = try XCTUnwrap(available(
            server(
                decision: .introductory,
                productID: monthlyID,
                activation: .immediate
            ),
            metadata(productID: monthlyID, kind: .introductory)
        ))
        let introductoryAttemptID = UUID()
        let introductoryRecoveryOnly = server(
            decision: .introductory,
            productID: monthlyID,
            activation: .immediate,
            state: .prepared,
            attemptID: introductoryAttemptID.uuidString,
            canPrepare: false
        )
        XCTAssertNil(IChartComplimentaryOfferPolicy.preparedAuthorization(
            response: introductoryRecoveryOnly,
            displayedOffer: introductoryOffer,
            attemptID: introductoryAttemptID
        ))
        XCTAssertEqual(
            IChartComplimentaryOfferPolicy.recoverablePreparedAttempt(
                response: introductoryRecoveryOnly,
                productID: monthlyID
            ),
            introductoryAttemptID
        )
    }

    func testMissingPreparationDeadlineFieldRemainsBackwardCompatible() {
        XCTAssertNotNil(available(
            server(
                decision: .introductory,
                productID: monthlyID,
                activation: .immediate,
                canPrepare: nil
            ),
            metadata(productID: monthlyID, kind: .introductory)
        ))
    }

    func testRedeemedStatusDoesNotCallAnEndedBenefitActive() throws {
        let ended = server(
            decision: .promotional,
            productID: monthlyID,
            offerID: "free-month",
            activation: .immediate,
            state: .redeemed,
            accessStartsAt: "2026-08-01T00:00:00Z",
            accessEndsAt: "2026-09-01T00:00:00Z"
        )
        let status = try XCTUnwrap(IChartComplimentaryOfferPolicy.confirmedStatus(response: ended))
        XCTAssertTrue(status.detailText.contains("ended"))
        XCTAssertFalse(status.detailText.contains("active through"))
    }

    func testOrdinaryTransactionsBypassCampaignResolutionWithoutPendingContext() {
        let accountID = UUID()

        XCTAssertFalse(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: monthlyID,
            appAccountToken: accountID,
            offerKind: nil,
            offerID: nil,
            pending: nil
        ))
        XCTAssertFalse(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: monthlyID,
            appAccountToken: accountID,
            offerKind: .introductory,
            offerID: nil,
            pending: nil
        ))
        XCTAssertFalse(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: "not-an-ichart-pro-product",
            appAccountToken: accountID,
            offerKind: .promotional,
            offerID: "ichart_complimentary_monthly_1m_v1",
            pending: nil
        ))
    }

    func testKnownPromotionalTransactionAlwaysRequiresCampaignResolution() {
        let unrelatedPending = IChartPendingComplimentaryPurchase(
            accountID: UUID(),
            productID: annualID,
            attemptID: UUID(),
            decision: .introductory,
            offerID: nil
        )
        for (productID, offerID) in [
            (monthlyID, "ichart_complimentary_monthly_1m_v1"),
            (annualID, "ichart_complimentary_annual_1m_v1")
        ] {
            XCTAssertTrue(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
                productID: productID,
                appAccountToken: nil,
                offerKind: .promotional,
                offerID: offerID,
                pending: nil
            ))
            XCTAssertFalse(IChartComplimentaryTransactionPolicy.matchesPendingContext(
                productID: productID,
                appAccountToken: UUID(),
                offerKind: .promotional,
                offerID: offerID,
                pending: unrelatedPending
            ))
        }
    }

    func testPendingContextBindsIntroductoryTransactionToAccountAndProduct() throws {
        let accountID = UUID()
        let pending = IChartPendingComplimentaryPurchase(
            accountID: accountID,
            productID: monthlyID,
            attemptID: UUID(),
            decision: .introductory,
            offerID: nil
        )

        XCTAssertTrue(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: monthlyID,
            appAccountToken: accountID,
            offerKind: .introductory,
            offerID: nil,
            pending: pending
        ))
        XCTAssertFalse(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: monthlyID,
            appAccountToken: UUID(),
            offerKind: .introductory,
            offerID: nil,
            pending: pending
        ))
        XCTAssertFalse(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: annualID,
            appAccountToken: accountID,
            offerKind: .introductory,
            offerID: nil,
            pending: pending
        ))
        XCTAssertFalse(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: monthlyID,
            appAccountToken: accountID,
            offerKind: .promotional,
            offerID: nil,
            pending: pending
        ))

        let decoded = try JSONDecoder().decode(
            IChartPendingComplimentaryPurchase.self,
            from: JSONEncoder().encode(pending)
        )
        XCTAssertEqual(decoded, pending)
    }

    func testScheduledPendingContextKeepsCurrentPaidTermInCampaignRecovery() {
        let accountID = UUID()
        let pending = IChartPendingComplimentaryPurchase(
            accountID: accountID,
            productID: annualID,
            attemptID: UUID(),
            decision: .scheduledPromotional,
            offerID: "ichart_complimentary_annual_1m_v1"
        )

        XCTAssertTrue(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: annualID,
            appAccountToken: accountID,
            offerKind: nil,
            offerID: nil,
            pending: pending
        ))
        XCTAssertFalse(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: annualID,
            appAccountToken: UUID(),
            offerKind: nil,
            offerID: nil,
            pending: pending
        ))
        XCTAssertFalse(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: monthlyID,
            appAccountToken: accountID,
            offerKind: nil,
            offerID: nil,
            pending: pending
        ))

        let immediatePending = IChartPendingComplimentaryPurchase(
            accountID: accountID,
            productID: annualID,
            attemptID: UUID(),
            decision: .promotional,
            offerID: "ichart_complimentary_annual_1m_v1"
        )
        XCTAssertFalse(IChartComplimentaryTransactionPolicy.requiresCampaignResolution(
            productID: annualID,
            appAccountToken: accountID,
            offerKind: nil,
            offerID: nil,
            pending: immediatePending
        ))
    }

    func testDisabledRecoveryOnlyScheduleIsDisplayableAndMatchesOnlyExistingPurchase() throws {
        let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let attempt = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        for (product, offerID) in [
            (monthlyID, "ichart_complimentary_monthly_1m_v1"),
            (annualID, "ichart_complimentary_annual_1m_v1")
        ] {
            let response = try recoveryStatus(overrides: ["productID": product, "offerID": offerID])
            let status = try XCTUnwrap(IChartComplimentaryOfferPolicy.confirmedStatus(response: response))
            XCTAssertEqual(status.state, .scheduled)
            XCTAssertNil(status.accessEndsAt)
            let pending = IChartPendingComplimentaryPurchase(
                accountID: owner, productID: product, attemptID: attempt,
                decision: .scheduledPromotional, offerID: offerID
            )
            XCTAssertTrue(IChartComplimentaryOfferPolicy.matchesConfirmedPurchase(
                response, pending: pending, accountID: owner, productID: product
            ))
            let offer = IChartComplimentaryOffer(
                campaignID: response.campaignID, productID: product, offerID: offerID,
                decision: .scheduledPromotional, activation: .nextBillingEvent,
                productDisplayName: "Synthetic Pro", offerDisplayPrice: "$0.00",
                renewalDisplayPrice: "$7.99", renewalPeriodDescription: "month"
            )
            XCTAssertTrue(IChartComplimentaryOfferPolicy.matchesConfirmedCampaign(
                response, offer: offer, attemptID: attempt
            ))
            XCTAssertFalse(IChartComplimentaryOfferPolicy.matchesConfirmedCampaign(
                response, offer: offer, attemptID: UUID()
            ))
        }
    }

    func testDisabledRecoveryOnlyRequiresExactIdentityFlagsStateAndScheduledDates() throws {
        let invalidOverrides: [[String: Any]] = [
            ["schemaVersion": 2], ["campaignID": "unknown-campaign"],
            ["productID": "unknown-product"], ["offerID": "unknown-offer"],
            ["offerID": "ichart_complimentary_annual_1m_v1"],
            ["attemptID": NSNull()], ["attemptID": "not-a-uuid"],
            ["enabled": true], ["recoveryOnly": false], ["recoveryOnly": NSNull()],
            ["canPrepare": true], ["canPrepare": NSNull()],
            ["decision": "promotional"], ["decision": "introductory"], ["decision": "ineligible"],
            ["activation": "immediate"], ["activation": NSNull()],
            ["state": "available"], ["state": "prepared"], ["state": "redeemed"], ["state": "unavailable"],
            ["serverTime": "not-a-date"], ["accessStartsAt": "not-a-date"],
            ["estimatedAccessEndsAt": "2026-12-01T00:00:00Z"],
            ["accessEndsAt": "2027-02-01T00:00:00Z"], ["accessEndsAtIsEstimated": false],
            ["signature": ["keyID": "synthetic-key", "nonce": UUID().uuidString,
                           "signature": derSignature(), "timestamp": 1_800_000_000]]
        ]
        let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let pending = IChartPendingComplimentaryPurchase(
            accountID: owner, productID: monthlyID,
            attemptID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            decision: .scheduledPromotional, offerID: "ichart_complimentary_monthly_1m_v1"
        )
        let offer = IChartComplimentaryOffer(
            campaignID: "ichart-complimentary-pro-1m-v1", productID: monthlyID,
            offerID: "ichart_complimentary_monthly_1m_v1", decision: .scheduledPromotional,
            activation: .nextBillingEvent, productDisplayName: "Synthetic Pro",
            offerDisplayPrice: "$0.00", renewalDisplayPrice: "$7.99", renewalPeriodDescription: "month"
        )
        for override in invalidOverrides {
            let response = try recoveryStatus(overrides: override)
            XCTAssertNil(IChartComplimentaryOfferPolicy.confirmedStatus(response: response), "\(override.keys.sorted())")
            XCTAssertFalse(IChartComplimentaryOfferPolicy.matchesConfirmedPurchase(
                response, pending: pending, accountID: owner, productID: monthlyID
            ), "\(override.keys.sorted())")
            XCTAssertFalse(IChartComplimentaryOfferPolicy.matchesConfirmedCampaign(
                response, offer: offer, attemptID: pending.attemptID
            ), "\(override.keys.sorted())")
        }
    }

    func testRecoveryOnlyCannotFinishWithoutSameOwnerCurrentPendingAttempt() throws {
        let response = try recoveryStatus()
        let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let attempt = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let cases: [IChartPendingComplimentaryPurchase?] = [
            nil,
            IChartPendingComplimentaryPurchase(accountID: UUID(), productID: monthlyID, attemptID: attempt,
                                               decision: .scheduledPromotional, offerID: response.offerID),
            IChartPendingComplimentaryPurchase(accountID: owner, productID: annualID, attemptID: attempt,
                                               decision: .scheduledPromotional, offerID: response.offerID),
            IChartPendingComplimentaryPurchase(accountID: owner, productID: monthlyID, attemptID: UUID(),
                                               decision: .scheduledPromotional, offerID: response.offerID),
            IChartPendingComplimentaryPurchase(accountID: owner, productID: monthlyID, attemptID: attempt,
                                               decision: .promotional, offerID: response.offerID),
            IChartPendingComplimentaryPurchase(accountID: owner, productID: monthlyID, attemptID: attempt,
                                               decision: .scheduledPromotional, offerID: "unknown-offer")
        ]
        for pending in cases {
            XCTAssertFalse(IChartComplimentaryOfferPolicy.matchesConfirmedPurchase(
                response, pending: pending, accountID: owner, productID: monthlyID
            ))
        }
        let pending = IChartPendingComplimentaryPurchase(
            accountID: owner, productID: monthlyID, attemptID: attempt,
            decision: .scheduledPromotional, offerID: response.offerID
        )
        XCTAssertFalse(IChartComplimentaryOfferPolicy.matchesConfirmedPurchase(
            response, pending: pending, accountID: UUID(), productID: monthlyID
        ))
        XCTAssertFalse(IChartComplimentaryOfferPolicy.matchesConfirmedPurchase(
            response, pending: pending, accountID: owner, productID: annualID
        ))
        var pendingObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pending)) as? [String: Any])
        pendingObject["version"] = 2
        let wrongVersion = try JSONDecoder().decode(IChartPendingComplimentaryPurchase.self,
            from: JSONSerialization.data(withJSONObject: pendingObject))
        XCTAssertFalse(IChartComplimentaryOfferPolicy.matchesConfirmedPurchase(
            response, pending: wrongVersion, accountID: owner, productID: monthlyID
        ))
    }

    func testRecoveryOnlyNeverCreatesAvailablePreparedOrNewPurchaseAuthorization() throws {
        let attempt = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let response = try recoveryStatus()
        let productMetadata = metadata(productID: monthlyID, offerID: response.offerID, kind: .promotional)
        let displayed = IChartComplimentaryOffer(
            campaignID: response.campaignID, productID: monthlyID, offerID: response.offerID,
            decision: .scheduledPromotional, activation: .nextBillingEvent,
            productDisplayName: "Synthetic Pro", offerDisplayPrice: "$0.00",
            renewalDisplayPrice: "$7.99", renewalPeriodDescription: "month"
        )
        for candidate in [response,
            try recoveryStatus(overrides: ["enabled": true, "canPrepare": true, "state": "available"]),
            try recoveryStatus(overrides: ["enabled": true, "canPrepare": true, "state": "prepared",
                "signature": ["keyID": "synthetic-key", "nonce": UUID().uuidString,
                              "signature": derSignature(), "timestamp": 1_800_000_000]])
        ] {
            XCTAssertNil(available(candidate, productMetadata))
            XCTAssertNil(IChartComplimentaryOfferPolicy.preparedAuthorization(
                response: candidate, displayedOffer: displayed, attemptID: attempt
            ))
            XCTAssertNil(IChartComplimentaryOfferPolicy.recoverablePreparedAttempt(
                response: candidate, productID: monthlyID
            ))
        }
    }

    func testRecoveryOnlyOptionalDecodingPreservesOrdinaryAndDiagnosticFields() throws {
        let ordinary = server(decision: .introductory, productID: monthlyID, activation: .immediate)
        var decoded = try JSONDecoder().decode(IChartComplimentaryOfferServerResponse.self,
            from: JSONEncoder().encode(ordinary))
        XCTAssertNil(decoded.recoveryOnly)
        XCTAssertNotNil(available(decoded, metadata(productID: monthlyID, kind: .introductory)))
        decoded.recoveryOnly = false
        XCTAssertNotNil(available(decoded, metadata(productID: monthlyID, kind: .introductory)))
        let recovery = try recoveryStatus(overrides: [
            "pendingVerificationChecks": ["syntheticBoundedCheck": true],
            "pendingDiscountCategory": "synthetic-bounded-category"
        ])
        XCTAssertEqual(recovery.recoveryOnly, true)
        XCTAssertEqual(recovery.pendingVerificationChecks, ["syntheticBoundedCheck": true])
        XCTAssertEqual(recovery.pendingDiscountCategory, "synthetic-bounded-category")
    }

    private func recoveryStatus(overrides: [String: Any] = [:]) throws -> IChartComplimentaryOfferServerResponse {
        var object: [String: Any] = [
            "schemaVersion": 1, "campaignID": "ichart-complimentary-pro-1m-v1", "enabled": false,
            "recoveryOnly": true, "canPrepare": false, "decision": "scheduledPromotional",
            "productID": monthlyID, "offerID": "ichart_complimentary_monthly_1m_v1",
            "activation": "nextBillingEvent", "state": "scheduled", "serverTime": "2026-10-08T12:00:00Z",
            "attemptID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "accessStartsAt": "2027-01-01T00:00:00Z", "estimatedAccessEndsAt": "2027-02-01T00:00:00Z",
            "accessEndsAtIsEstimated": true
        ]
        for (key, value) in overrides { object[key] = value }
        return try JSONDecoder().decode(IChartComplimentaryOfferServerResponse.self,
            from: JSONSerialization.data(withJSONObject: object))
    }

    private func available(
        _ response: IChartComplimentaryOfferServerResponse,
        _ metadata: IChartComplimentaryOfferProductMetadata
    ) -> IChartComplimentaryOffer? {
        IChartComplimentaryOfferPolicy.availableOffer(
            response: response,
            metadata: metadata,
            appleIntroEligible: true
        )
    }

    private func metadata(
        productID: String,
        offerID: String? = nil,
        kind: IChartComplimentaryOfferProductMetadata.OfferKind,
        price: Decimal = .zero,
        mode: IChartComplimentaryOfferProductMetadata.PaymentMode = .freeTrial,
        period: IChartComplimentaryOfferProductMetadata.Period = .months(1),
        periodCount: Int = 1,
        renewalPeriod: IChartComplimentaryOfferProductMetadata.Period = .months(1)
    ) -> IChartComplimentaryOfferProductMetadata {
        IChartComplimentaryOfferProductMetadata(
            productID: productID,
            productDisplayName: productID == annualID ? "Annual Pro" : "Monthly Pro",
            renewalDisplayPrice: productID == annualID ? "$64.99" : "$7.99",
            renewalPeriod: renewalPeriod,
            offerID: offerID,
            offerKind: kind,
            offerPrice: price,
            offerDisplayPrice: "$0.00",
            offerPeriod: period,
            offerPeriodCount: periodCount,
            paymentMode: mode
        )
    }

    private func server(
        enabled: Bool = true,
        decision: IChartComplimentaryOfferDecision,
        productID: String,
        offerID: String? = nil,
        activation: IChartComplimentaryOfferActivation?,
        state: IChartComplimentaryOfferServerState = .available,
        signature: IChartComplimentaryOfferServerSignature? = nil,
        attemptID: String? = nil,
        accessStartsAt: String? = nil,
        accessEndsAt: String? = nil,
        estimatedAccessEndsAt: String? = nil,
        accessEndsAtIsEstimated: Bool? = nil,
        canPrepare: Bool? = nil
    ) -> IChartComplimentaryOfferServerResponse {
        IChartComplimentaryOfferServerResponse(
            schemaVersion: 1,
            campaignID: "one-month-free-2026",
            enabled: enabled,
            decision: decision,
            productID: productID,
            offerID: offerID,
            activation: activation,
            state: state,
            serverTime: "2026-10-08T12:00:00Z",
            accessStartsAt: accessStartsAt,
            accessEndsAt: accessEndsAt,
            estimatedAccessEndsAt: estimatedAccessEndsAt,
            accessEndsAtIsEstimated: accessEndsAtIsEstimated,
            reason: nil,
            signature: signature,
            attemptID: attemptID,
            canPrepare: canPrepare
        )
    }

    private func signature() -> IChartComplimentaryOfferServerSignature {
        IChartComplimentaryOfferServerSignature(
            keyID: "apple-key",
            nonce: UUID().uuidString,
            signature: derSignature(),
            timestamp: 1_800_000_000
        )
    }

    private func derSignature() -> String {
        Data([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01]).base64EncodedString()
    }
}

final class IChartComplimentaryOfferIntegrationTests: XCTestCase {
    func testRecoveryStatusAcknowledgesOnlyMatchingPendingSnapshotAfterFinalOwnerCheck() throws {
        let storeText = try source("iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift")
        let start = try XCTUnwrap(storeText.range(of: "private func refreshComplimentaryOffers()"))
        let end = try XCTUnwrap(storeText.range(of: "private func resolvedComplimentaryOffer(", range: start.upperBound..<storeText.endIndex))
        let body = String(storeText[start.lowerBound..<end.lowerBound])
        let confirmedStatus = try XCTUnwrap(body.range(of: "if let status = IChartComplimentaryOfferPolicy.confirmedStatus(response: response)"))
        let recoveryOnly = try XCTUnwrap(body.range(of: "if response.recoveryOnly == true", range: confirmedStatus.upperBound..<body.endIndex))
        let matchingPurchase = try XCTUnwrap(body.range(of: "IChartComplimentaryOfferPolicy.matchesConfirmedPurchase(", range: recoveryOnly.upperBound..<body.endIndex))
        let collected = try XCTUnwrap(body.range(of: "acknowledgedPendingPurchases.append(pending)", range: matchingPurchase.upperBound..<body.endIndex))
        let finalOwner = try XCTUnwrap(body.range(of: "guard try await subscriptionClaimService.appAccountToken() == initialAccountID", range: collected.upperBound..<body.endIndex))
        let unchangedSnapshot = try XCTUnwrap(body.range(of: "guard pendingComplimentaryPurchase() == pending else", range: finalOwner.upperBound..<body.endIndex))
        let removeMarker = try XCTUnwrap(body.range(of: "removePendingComplimentaryPurchase(attemptID: pending.attemptID)", range: unchangedSnapshot.upperBound..<body.endIndex))
        XCTAssertLessThan(confirmedStatus.lowerBound, recoveryOnly.lowerBound)
        XCTAssertLessThan(recoveryOnly.lowerBound, matchingPurchase.lowerBound)
        XCTAssertLessThan(matchingPurchase.lowerBound, collected.lowerBound)
        XCTAssertLessThan(collected.lowerBound, finalOwner.lowerBound)
        XCTAssertLessThan(finalOwner.lowerBound, unchangedSnapshot.lowerBound)
        XCTAssertLessThan(unchangedSnapshot.lowerBound, removeMarker.lowerBound)
        XCTAssertTrue(body.contains("accountID: initialAccountID"))
        XCTAssertTrue(body.contains("productID: product.id"))
        XCTAssertFalse(body.contains("await transaction.finish()"))
        XCTAssertFalse(body.contains("entitlement ="))
        XCTAssertFalse(body.contains("product.purchase("))
        let acknowledgement = String(body[finalOwner.upperBound..<removeMarker.upperBound])
        XCTAssertFalse(acknowledgement.contains("await "))
    }

    func testDisabledRecoveryRequiresPendingAttemptAndOwnerBeforeConfirmedStatusShortcut() throws {
        let storeText = try source("iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift")
        let start = try XCTUnwrap(storeText.range(of: "private func complimentaryTransactionResolution("))
        let end = try XCTUnwrap(storeText.range(of: "private func pendingComplimentaryPurchase()", range: start.upperBound..<storeText.endIndex))
        let body = String(storeText[start.lowerBound..<end.lowerBound])
        let recovery = try XCTUnwrap(body.range(of: "if status.recoveryOnly == true"))
        let ordinary = try XCTUnwrap(body.range(of: "if IChartComplimentaryOfferPolicy.confirmedStatus"))
        let branch = String(body[recovery.lowerBound..<ordinary.lowerBound])
        XCTAssertTrue(branch.contains("matchesPendingContext("))
        XCTAssertTrue(branch.contains("matchesConfirmedPurchase("))
        XCTAssertTrue(branch.contains("pending: pending"))
        XCTAssertTrue(branch.contains("pendingComplimentaryPurchase() == pending"))
        let ownerCheck = try XCTUnwrap(branch.range(of: "subscriptionClaimService.appAccountToken() == accountID"))
        let confirmed = try XCTUnwrap(branch.range(of: "return .confirmedCampaign"))
        XCTAssertLessThan(ownerCheck.lowerBound, confirmed.lowerBound)
        XCTAssertFalse(branch.contains("entitlement ="))
        XCTAssertFalse(branch.contains(".purchase("))
    }

    func testCampaignTransportPinsGenuineSessionAndRetainsBoundedDiagnosticHooks() throws {
        let storeText = try source("iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift")
        let start = try XCTUnwrap(storeText.range(of: "private func invokeComplimentaryOffer("))
        let end = try XCTUnwrap(storeText.range(of: "private func refreshedSession()", range: start.upperBound..<storeText.endIndex))
        let body = String(storeText[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(body.contains("authenticatedDataClient(for: session)"))
        XCTAssertTrue(body.contains("ownerClient.functions.invoke("))
        let ownerCheck = try XCTUnwrap(body.range(of: "authClient.auth.session.user.id == session.user.id"))
        let result = try XCTUnwrap(body.range(of: "return response"))
        XCTAssertLessThan(ownerCheck.lowerBound, result.lowerBound)
        XCTAssertTrue(storeText.contains("IChartComplimentaryOfferQADiagnostics.recordPendingChecks("))
        XCTAssertTrue(storeText.contains("IChartComplimentaryOfferQADiagnostics.sanitizedResponse("))
        XCTAssertTrue(storeText.contains("IChartComplimentaryOfferQADiagnostics.sanitizedRequestError("))
    }

    func testCampaignPurchaseIsSeparateFromOrdinaryPaidFallback() throws {
        let storeText = try source("iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift")
        let campaignBody = try XCTUnwrap(
            storeText.range(of: "func purchaseComplimentaryOffer(")
                .flatMap { start in
                    storeText.range(of: "func restorePurchases()", range: start.upperBound..<storeText.endIndex)
                        .map { String(storeText[start.lowerBound..<$0.lowerBound]) }
                }
        )

        XCTAssertTrue(campaignBody.contains("let attemptID = UUID()"))
        XCTAssertTrue(campaignBody.contains("guard !complimentaryPurchaseInFlight"))
        XCTAssertTrue(campaignBody.contains("action: .status"))
        XCTAssertTrue(campaignBody.contains("action: .prepare"))
        XCTAssertTrue(campaignBody.contains("action: .confirm"))
        XCTAssertTrue(campaignBody.contains(".appAccountToken(accountID)"))
        XCTAssertTrue(campaignBody.contains(".promotionalOffer("))
        XCTAssertTrue(campaignBody.contains("product.purchase(options: purchaseOptions)"))
        XCTAssertTrue(campaignBody.contains("subscriptionClaimService.claim("))
        XCTAssertTrue(campaignBody.contains("never finish it after the signed-in account changes"))
        XCTAssertFalse(campaignBody.contains("await purchase(product)"))
        XCTAssertFalse(campaignBody.contains("applyLocalPreview"))

        let claim = try XCTUnwrap(campaignBody.range(of: "subscriptionClaimService.claim("))
        let confirm = try XCTUnwrap(campaignBody.range(of: "action: .confirm"))
        let finish = try XCTUnwrap(campaignBody.range(of: "await transaction.finish()"))
        XCTAssertLessThan(claim.lowerBound, confirm.lowerBound)
        XCTAssertLessThan(confirm.lowerBound, finish.lowerBound)
        XCTAssertTrue(storeText.contains("recoverUnfinishedTransactions()"))
        XCTAssertTrue(storeText.contains("matchesRecoveredConfirmation"))
        XCTAssertTrue(storeText.contains("hasActiveVerifiedEntitlement(for: product.id)"))
    }

    func testOrdinaryTransactionGatePrecedesOptionalCampaignSessionAndEndpoint() throws {
        let storeText = try source("iChart/App/StoreKit/IChartStoreKitSubscriptionStore.swift")
        let body = try XCTUnwrap(
            storeText.range(of: "private func complimentaryTransactionResolution(")
                .flatMap { start in
                    storeText.range(
                        of: "private func pendingComplimentaryPurchase()",
                        range: start.upperBound..<storeText.endIndex
                    ).map { String(storeText[start.lowerBound..<$0.lowerBound]) }
                }
        )

        let policyGate = try XCTUnwrap(body.range(of: "requiresCampaignResolution("))
        let serviceGate = try XCTUnwrap(body.range(of: "guard let subscriptionClaimService"))
        let accountLookup = try XCTUnwrap(body.range(of: "subscriptionClaimService.appAccountToken()"))
        let statusRequest = try XCTUnwrap(body.range(of: "action: .status"))

        XCTAssertLessThan(policyGate.lowerBound, serviceGate.lowerBound)
        XCTAssertLessThan(serviceGate.lowerBound, accountLookup.lowerBound)
        XCTAssertLessThan(accountLookup.lowerBound, statusRequest.lowerBound)
        XCTAssertTrue(body.contains("guard let subscriptionClaimService else"))
        XCTAssertEqual(body.components(separatedBy: "return .notCampaign").count - 1, 1)
        XCTAssertFalse(body.contains("!status.enabled"))
        XCTAssertFalse(body.contains("status.state == .unavailable"))
    }

    func testBothSubscriptionSurfacesUseDedicatedCampaignAction() throws {
        let upgrade = try source("iChart/Features/Editor/Components/UpgradeSheetView.swift")
        let library = try source("iChart/Features/Library/LibraryView.swift")

        for text in [upgrade, library] {
            XCTAssertTrue(text.contains("subscriptionStore.complimentaryOffers"))
            XCTAssertTrue(text.contains("subscriptionStore.purchaseComplimentaryOffer(offer)"))
            XCTAssertTrue(text.contains("One Month Free"))
            XCTAssertTrue(text.contains("Standard paid plans"))
        }
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath))
    }
}
