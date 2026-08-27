import XCTest
@testable import iChart

final class ChordInkSequentialGrouperTests: XCTestCase {
    private let grouper = ChordInkSequentialGrouper()

    func testGroupsDMinorSevenEMinorSevenByRootStarts() throws {
        let strokes = try glyphStrokes([
            ("D", 0), ("-", 0), ("7", 0),
            ("E", 118), ("-", 118), ("7", 118)
        ])

        let groups = grouper.groups(for: indexed(strokes))

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].rootText, "D")
        XCTAssertEqual(groups[0].strokeIndices, [0, 1, 2, 3])
        XCTAssertEqual(groups[1].rootText, "E")
        XCTAssertEqual(groups[1].strokeIndices, [4, 5, 6, 7])
    }

    func testGroupsMajorTriangleAndMinorExtensionsByRootStarts() throws {
        let strokes = try glyphStrokes([
            ("C", 0), ("△", 0), ("7", 0),
            ("D", 118), ("-", 118), ("7", 118),
            ("E", 236), ("-", 236), ("9", 236)
        ])

        let groups = grouper.groups(for: indexed(strokes))

        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.rootText), ["C", "D", "E"])
        XCTAssertEqual(groups[0].strokeIndices, [0, 1, 2])
        XCTAssertEqual(groups[1].strokeIndices, [3, 4, 5, 6])
        XCTAssertEqual(groups[2].strokeIndices, [7, 8, 9, 10])
    }

    func testSuffixOnlyFragmentsDoNotCreateIndependentChordGroups() throws {
        let strokes = try glyphStrokes([
            ("-", 0), ("7", 0), ("9", 0)
        ])

        let groups = grouper.groups(for: indexed(strokes))

        XCTAssertTrue(groups.isEmpty)
    }

    func testSoloVerticalBarlineLikeStrokeDoesNotCreateChordGroup() {
        let barline = InkStroke(points: [
            InkPoint(x: 24, y: 12, timeOffset: nil),
            InkPoint(x: 24, y: 62, timeOffset: nil)
        ])

        let groups = grouper.groups(for: indexed([barline]))

        XCTAssertTrue(groups.isEmpty)
    }

    func testTightAdjacentRootsSplitEvenWhenGapFallbackWouldKeepOneGroup() throws {
        let strokes = try glyphStrokes([
            ("C", 0),
            ("D", 55)
        ])

        let sequentialGroups = grouper.groups(for: indexed(strokes))
        let gapClusters = ChordInkBatchClusterer.clusters(for: strokes)

        XCTAssertEqual(gapClusters.count, 1)
        XCTAssertEqual(sequentialGroups.count, 2)
        XCTAssertEqual(sequentialGroups.map(\.rootText), ["C", "D"])
    }

    func testDetachedLowConfidenceRootSizedDStartsNextGroupAfterC() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("D", confidence: 0.541),
                glyph("B", confidence: 0.533),
                glyph("△", confidence: 0.521),
                glyph("b", confidence: 0.46),
                glyph("A", confidence: 0.452)
            ],
            cluster: cluster(rootBounds(at: 82)),
            currentGroupBounds: rootBounds(at: 0),
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertEqual(evidence?.text, "D")
    }

    func testCloseAdjacentRootSizedLetterStartsNextGroupAtLiveTraceGap() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("E", confidence: 0.996, source: .heuristic),
                glyph("5", confidence: 0.992, source: .heuristic),
                glyph("6", confidence: 0.49)
            ],
            cluster: cluster(rootBounds(at: 46)),
            currentGroupBounds: rootBounds(at: 0),
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertEqual(evidence?.text, "E")
    }

    func testDeviceCThenDetachedDStaysAsSeparateSequentialGroups() {
        let groups = grouper.groups(for: indexed(deviceCThenDetachedDStrokes()))

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.rootText), ["C", "D"])
        XCTAssertEqual(groups[0].strokeIndices, [0])
        XCTAssertEqual(groups[1].strokeIndices, [1, 2])
    }

    func testRepeatDeviceCThenDetachedDStaysSeparateAtFallbackGapBoundary() {
        let groups = grouper.groups(for: indexed(repeatDeviceCThenDetachedDStrokes()))

        XCTAssertEqual(groups.count, 2)
        guard groups.count == 2 else {
            return
        }
        XCTAssertEqual(groups.map(\.rootText), ["C", "D"])
        XCTAssertEqual(groups[0].strokeIndices, [0])
        XCTAssertEqual(groups[1].strokeIndices, [1, 2])
    }

    func testLatestDeviceCThenDetachedDRepeatKeepsEveryRootGroupSeparate() {
        let groups = grouper.groups(for: indexed(latestRepeatDeviceCThenDetachedDStrokes()))

        XCTAssertEqual(groups.count, 4)
        guard groups.count == 4 else {
            return
        }
        XCTAssertEqual(groups.map(\.rootText), ["C", "D", "C", "D"])
        XCTAssertEqual(groups[0].strokeIndices, [0])
        XCTAssertEqual(groups[1].strokeIndices, [1, 2])
        XCTAssertEqual(groups[2].strokeIndices, [3])
        XCTAssertEqual(groups[3].strokeIndices, [4, 5])
    }

    func testLatestRhythmCloseCThenFragmentedFStaysSeparateBeforeGapFallback() {
        let strokes = latestRhythmCloseCThenFragmentedFStrokes()
        let strokeClusters = StrokeClusterer().indexedClusters(strokes)
        let groups = grouper.groups(for: indexed(strokes))

        XCTAssertEqual(
            strokeClusters.count,
            2,
            "The lower-level clusterer splits the live C/F trace, but the first C still has to survive initial root evidence before fallback can collapse it."
        )
        XCTAssertEqual(groups.count, 2)
        guard groups.count == 2 else {
            return
        }
        XCTAssertEqual(groups.map(\.rootText), ["C", "F"])
        XCTAssertEqual(groups[0].strokeIndices, [0])
        XCTAssertEqual(groups[1].strokeIndices, [1, 2, 3])
    }

    func testSlashBassRootDoesNotStartASecondGroup() throws {
        let strokes = try glyphStrokes([
            ("G", 0),
            ("/", 0),
            ("B", 78)
        ])

        let groups = grouper.groups(for: indexed(strokes))

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].rootText, "G")
        XCTAssertEqual(groups[0].strokeIndices, [0, 1, 2, 3])
    }

    func testDetachedRootSizedFlatLookalikeCanStartNextGroup() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("b", confidence: 0.98),
                glyph("C", confidence: 0.965, source: .heuristic)
            ],
            cluster: cluster(rootBounds(at: 100)),
            currentGroupBounds: rootBounds(at: 0),
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertEqual(evidence?.text, "C")
    }

    func testDetachedRootSizedFlatLookalikeStartsNextGroupWhenRootTrailsByLiveTraceMargin() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("b", confidence: 0.98, source: .heuristic),
                glyph("D", confidence: 0.92, source: .heuristic)
            ],
            cluster: cluster(rootBounds(at: 100)),
            currentGroupBounds: rootBounds(at: 0),
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertEqual(evidence?.text, "D")
    }

    func testAttachedFlatLookalikeDoesNotStartNextGroup() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("b", confidence: 0.98),
                glyph("C", confidence: 0.95, source: .heuristic)
            ],
            cluster: cluster(highSuffixBounds(at: 42)),
            currentGroupBounds: rootBounds(at: 0),
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertNil(evidence)
    }

    func testBaseSizedInitialFlatLookalikeCanStartRootWhenRootEvidenceIsClose() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("b", confidence: 0.98, source: .heuristic),
                glyph("C", confidence: 0.95, source: .heuristic)
            ],
            cluster: cluster(InkBounds(minX: 52, minY: 16, maxX: 74, maxY: 44)),
            currentGroupBounds: nil,
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertEqual(evidence?.text, "C")
    }

    func testBaseSizedInitialExtensionLookalikeCanStartRootWhenRootEvidenceIsClose() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("6", confidence: 0.995, source: .heuristic),
                glyph("C", confidence: 0.95, source: .heuristic)
            ],
            cluster: cluster(InkBounds(minX: 52, minY: 16, maxX: 76, maxY: 46)),
            currentGroupBounds: nil,
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertEqual(evidence?.text, "C")
    }

    func testBaseSizedInitialExtensionLookalikeDoesNotStartRootWhenRootEvidenceTrailsTooFar() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("6", confidence: 0.995, source: .heuristic),
                glyph("C", confidence: 0.88, source: .heuristic)
            ],
            cluster: cluster(InkBounds(minX: 52, minY: 16, maxX: 76, maxY: 46)),
            currentGroupBounds: nil,
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertNil(evidence)
    }

    func testCompactInitialFlatLookalikeDoesNotStartRoot() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("b", confidence: 0.98, source: .heuristic),
                glyph("C", confidence: 0.95, source: .heuristic)
            ],
            cluster: cluster(highSuffixBounds(at: 42)),
            currentGroupBounds: nil,
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertNil(evidence)
    }

    func testDetachedRootSizedMinorLookalikeCanStartNextGroup() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("m", confidence: 0.99),
                glyph("G", confidence: 0.97, source: .heuristic)
            ],
            cluster: cluster(rootBounds(at: 100)),
            currentGroupBounds: rootBounds(at: 0),
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertEqual(evidence?.text, "G")
    }

    func testDetachedNineLookalikeDoesNotStartFakeCGroup() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("9", confidence: 1.0),
                glyph("C", confidence: 0.95, source: .heuristic)
            ],
            cluster: cluster(rootBounds(at: 100)),
            currentGroupBounds: rootBounds(at: 0),
            previousGlyphWasSlashSeparator: false
        )

        XCTAssertNil(evidence)
    }

    func testSlashBassRootEvidenceDoesNotStartNextGroup() {
        let evidence = ChordInkSequentialRootStartDetector.evidence(
            in: [
                glyph("B", confidence: 0.96, source: .heuristic)
            ],
            cluster: cluster(rootBounds(at: 74)),
            currentGroupBounds: InkBounds(minX: 0, minY: 10, maxX: 60, maxY: 60),
            previousGlyphWasSlashSeparator: true
        )

        XCTAssertNil(evidence)
    }

    func testAddingRightSideInkDoesNotChangeClosedGroupBoundaries() throws {
        let firstPass = try glyphStrokes([
            ("D", 0), ("-", 0), ("7", 0),
            ("E", 118), ("-", 118), ("7", 118)
        ])
        let secondPass = try glyphStrokes([
            ("D", 0), ("-", 0), ("7", 0),
            ("E", 118), ("-", 118), ("7", 118),
            ("F", 236), ("-", 236), ("7", 236)
        ])

        let firstGroups = grouper.groups(for: indexed(firstPass))
        let secondGroups = grouper.groups(for: indexed(secondPass))

        XCTAssertEqual(secondGroups.count, 3)
        XCTAssertEqual(Array(secondGroups.prefix(2)).map(\.strokeIndices), firstGroups.map(\.strokeIndices))
        XCTAssertEqual(Array(secondGroups.prefix(2)).map(\.rootText), firstGroups.map(\.rootText))
    }

    private func glyphStrokes(_ glyphs: [(String, Double)]) throws -> [InkStroke] {
        try glyphs.flatMap { text, offsetX in
            try templateStrokes(text, offsetX: offsetX)
        }
    }

    private func templateStrokes(_ text: String, offsetX: Double) throws -> [InkStroke] {
        let template = try XCTUnwrap(
            ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == text },
            "Missing template \(text)"
        )

        return template.strokes.map { stroke in
            InkStroke(
                points: stroke.points.map { point in
                    InkPoint(
                        x: point.x + offsetX,
                        y: point.y,
                        timeOffset: point.timeOffset
                    )
                }
            )
        }
    }

    private func indexed(_ strokes: [InkStroke]) -> [(index: Int, stroke: InkStroke)] {
        strokes.enumerated().map { index, stroke in
            (index: index, stroke: stroke)
        }
    }

    private func glyph(
        _ text: String,
        confidence: Double,
        source: RecognitionSource = .template
    ) -> GlyphCandidate {
        GlyphCandidate(text: text, confidence: confidence, source: source)
    }

    private func cluster(_ bounds: InkBounds) -> InkCluster {
        InkCluster(strokes: [], bounds: bounds)
    }

    private func rootBounds(at x: Double) -> InkBounds {
        InkBounds(minX: x, minY: 10, maxX: x + 34, maxY: 60)
    }

    private func highSuffixBounds(at x: Double) -> InkBounds {
        InkBounds(minX: x, minY: 14, maxX: x + 14, maxY: 34)
    }

    private func latestDeviceStroke(_ points: [(Double, Double)]) -> InkStroke {
        InkStroke(
            points: points.map { x, y in
                InkPoint(x: x, y: y, timeOffset: nil)
            }
        )
    }

    private func latestRhythmCloseCThenFragmentedFStrokes() -> [InkStroke] {
        [
            latestDeviceStroke([
                (65.4787826538086, 16.66763687133789),
                (64.55601501464844, 17.921964645385742),
                (62.71050262451172, 19.572410583496094),
                (60.99680709838867, 21.486923217773438),
                (59.94222640991211, 22.8072566986084),
                (58.88763427734375, 24.391695022583008),
                (57.701236724853516, 26.240163803100586),
                (56.580745697021484, 28.286727905273438),
                (55.460243225097656, 30.531314849853516),
                (54.339752197265625, 33.106014251708984),
                (53.54882049560547, 35.28459167480469),
                (52.95561218261719, 37.39716339111328),
                (52.62605667114258, 39.24563217163086),
                (52.62605667114258, 43.07465744018555),
                (53.94428634643555, 43.93290328979492),
                (56.05344772338867, 44.13096237182617),
                (58.953556060791016, 44.13096237182617),
                (60.469512939453125, 43.86689376831055),
                (62.051387786865234, 43.40476989746094),
                (63.69917678833008, 42.87663650512695),
                (65.28104400634766, 42.2824592590332),
                (66.92882537841797, 41.62227249145508),
                (68.64252471923828, 40.96212387084961),
                (70.02666473388672, 40.36794662475586),
                (72.39947509765625, 39.44369125366211),
                (74.11316680908203, 38.651493072509766)
            ]),
            latestDeviceStroke([
                (107.53024291992188, 23.797517776489258),
                (106.87113189697266, 20.76072883605957),
                (106.80522155761719, 22.543190002441406),
                (107.06885528564453, 24.589754104614258),
                (107.53024291992188, 27.098407745361328),
                (107.99163055419922, 29.871166229248047),
                (108.18936157226562, 31.521575927734375),
                (108.5848388671875, 34.16228103637695),
                (108.98029327392578, 36.60496520996094),
                (109.5075912475586, 39.509735107421875),
                (109.90306854248047, 41.22618865966797)
            ]),
            latestDeviceStroke([
                (109.24394989013672, 20.95875358581543),
                (108.78256225585938, 19.506366729736328),
                (111.68266296386719, 18.450098037719727),
                (113.79182434082031, 17.789913177490234),
                (117.2192153930664, 16.931703567504883),
                (119.65794372558594, 16.46957778930664),
                (121.63529205322266, 16.27151870727539),
                (123.21715545654297, 16.27151870727539),
                (124.46947479248047, 16.20551109313965)
            ]),
            latestDeviceStroke([
                (111.02354431152344, 30.465307235717773),
                (112.93498229980469, 30.465307235717773),
                (116.16464233398438, 29.276988983154297),
                (118.1419906616211, 28.616802215576172),
                (122.49213409423828, 27.296466827392578)
            ])
        ]
    }

    private func latestRepeatDeviceCThenDetachedDStrokes() -> [InkStroke] {
        [
            latestDeviceStroke([
                (53.27898406982422, 46.01839065551758),
                (53.60853958129883, 43.311676025390625),
                (52.09257125854492, 44.43395233154297),
                (50.312965393066406, 46.41450881958008),
                (49.12656784057617, 47.80085372924805),
                (47.742427825927734, 49.451297760009766),
                (46.094642639160156, 51.497859954833984),
                (44.31503677368164, 53.80845642089844),
                (42.271785736083984, 56.51520538330078),
                (40.3603515625, 59.15591049194336),
                (38.31709671020508, 61.9946403503418),
                (36.405662536621094, 65.09747314453125),
                (34.56014633178711, 68.26631164550781),
                (32.978271484375, 71.5011978149414),
                (31.462312698364258, 75.00010681152344),
                (30.737289428710938, 77.70685577392578),
                (30.407732009887695, 80.08349609375),
                (30.407732009887695, 82.1300277709961),
                (30.47364044189453, 83.84648132324219),
                (31.26457405090332, 85.23285675048828),
                (32.385074615478516, 86.42118072509766),
                (33.83512496948242, 86.88330078125),
                (35.54882049560547, 87.01531982421875),
                (37.52616500854492, 87.01531982421875),
                (39.76714324951172, 87.01531982421875),
                (42.13995361328125, 86.4871826171875),
                (44.90822982788086, 85.8270034790039),
                (47.28104019165039, 84.90278625488281),
                (49.71976089477539, 83.84648132324219)
            ]),
            latestDeviceStroke([
                (111.41282653808594, 53.94050598144531),
                (111.61054992675781, 55.92102813720703),
                (112.2037582397461, 58.69378662109375),
                (112.5333251953125, 60.212181091308594),
                (112.79695892333984, 61.79661560058594),
                (113.06062316894531, 63.579078674316406),
                (113.25834655761719, 65.49359130859375),
                (113.4560775756836, 67.54012298583984),
                (113.71973419189453, 69.78474426269531),
                (113.91746520996094, 71.63320922851562),
                (114.04928588867188, 73.41571044921875),
                (114.24700927734375, 74.9341049194336),
                (114.44476318359375, 77.31073760986328),
                (114.7083969116211, 79.35730743408203)
            ]),
            latestDeviceStroke([
                (108.18315887451172, 52.81819534301758),
                (107.98543548583984, 51.233795166015625),
                (107.8536148071289, 49.71536636352539),
                (108.05133819580078, 47.9989128112793),
                (109.56729888916016, 46.34846496582031),
                (111.67648315429688, 44.896080017089844),
                (113.06062316894531, 44.16988754272461),
                (115.82890319824219, 43.57574462890625),
                (117.34485626220703, 43.57574462890625),
                (119.05854034423828, 43.57574462890625),
                (120.8381576538086, 44.103878021240234),
                (122.88140869140625, 44.96212387084961),
                (124.66102600097656, 46.08440017700195),
                (126.50653076171875, 47.47077560424805),
                (128.35205078125, 49.055213928222656),
                (130.26348876953125, 50.77166748046875),
                (132.04307556152344, 52.62013626098633),
                (134.0204315185547, 54.79875183105469),
                (135.47047424316406, 56.779273986816406),
                (136.65689086914062, 58.95785140991211),
                (137.64556884765625, 61.20243835449219),
                (138.3046875, 63.381019592285156),
                (138.6342315673828, 65.49359130859375),
                (138.76605224609375, 67.87023162841797),
                (138.76605224609375, 69.78474426269531),
                (138.04103088378906, 71.7652587890625),
                (136.92054748535156, 73.61376953125),
                (135.53640747070312, 75.46223449707031),
                (133.88861083984375, 77.24473571777344),
                (131.91127014160156, 79.22525024414062),
                (129.9339141845703, 80.61163330078125),
                (127.89067077636719, 81.86595916748047),
                (125.7155990600586, 82.98827362060547),
                (123.60643005371094, 83.91252136230469),
                (121.43136596679688, 84.57266998291016),
                (119.12445068359375, 85.1008071899414),
                (117.4107666015625, 85.23285675048828),
                (115.89480590820312, 85.23285675048828),
                (113.52198791503906, 84.57266998291016),
                (111.87421417236328, 82.85621643066406),
                (111.54463958740234, 79.88543701171875),
                (112.00602722167969, 78.03693389892578)
            ]),
            latestDeviceStroke([
                (204.41380310058594, 49.51734161376953),
                (205.4683837890625, 48.19697189331055),
                (207.0502471923828, 46.81059265136719),
                (208.56622314453125, 46.21644973754883),
                (207.9730224609375, 48.461036682128906),
                (207.11614990234375, 49.71536636352539),
                (206.06158447265625, 51.233795166015625),
                (204.80926513671875, 53.01625442504883),
                (203.35922241210938, 54.99677658081055),
                (201.77734375, 57.17535400390625),
                (199.93182373046875, 59.55199432373047),
                (198.21812438964844, 61.79661560058594),
                (196.5044403076172, 64.1732177734375),
                (194.9225616455078, 66.61590576171875),
                (193.4724884033203, 69.12455749511719),
                (192.4179229736328, 71.63320922851562),
                (191.69290161132812, 74.27391815185547),
                (191.69290161132812, 76.18843078613281),
                (191.890625, 77.70685577392578),
                (193.1429443359375, 78.82913208007812),
                (194.9884796142578, 79.42330932617188),
                (197.16354370117188, 79.48931884765625),
                (199.8659210205078, 79.48931884765625),
                (202.43646240234375, 79.09320068359375),
                (205.27064514160156, 78.10294342041016),
                (208.3025665283203, 76.84861755371094),
                (211.40040588378906, 75.46223449707031),
                (214.4323272705078, 74.00984954833984),
                (217.6619873046875, 72.42544555664062)
            ]),
            latestDeviceStroke([
                (276.7845153808594, 57.3734130859375),
                (276.7185974121094, 55.52494430541992),
                (277.3117980957031, 57.50546646118164),
                (278.23455810546875, 60.410240173339844),
                (278.7618713378906, 62.19269943237305),
                (279.35504150390625, 64.1732177734375),
                (279.8164367675781, 66.15377807617188),
                (280.3437194824219, 68.20030212402344),
                (280.87103271484375, 70.3788833618164),
                (281.4642333984375, 72.55746459960938),
                (282.0574035644531, 74.73604583740234),
                (282.7165222167969, 77.04667663574219),
                (283.17791748046875, 78.6971206665039),
                (284.16656494140625, 80.87570190429688)
            ]),
            latestDeviceStroke([
                (271.9070739746094, 52.81819534301758),
                (272.3025207519531, 50.77166748046875),
                (272.9616394042969, 49.055213928222656),
                (274.41168212890625, 47.33872604370117),
                (276.7845153808594, 45.688316345214844),
                (279.7505187988281, 44.83007049560547),
                (281.3982849121094, 44.63201141357422),
                (283.4415588378906, 44.63201141357422),
                (285.68255615234375, 44.63201141357422),
                (288.5167236328125, 44.83007049560547),
                (291.2191162109375, 45.5562629699707),
                (294.11920166015625, 46.54652404785156),
                (297.0852355957031, 47.73484420776367),
                (300.05120849609375, 49.18722915649414),
                (302.8854064941406, 50.705623626708984),
                (305.7855224609375, 52.55413055419922),
                (307.8287658691406, 54.27058410644531),
                (309.5424499511719, 56.185096740722656),
                (310.8606872558594, 58.16561508178711),
                (311.915283203125, 60.2781867980957),
                (312.6402893066406, 62.32475280761719),
                (313.1676025390625, 64.5693359375),
                (313.1676025390625, 66.35183715820312),
                (313.1676025390625, 68.1343002319336),
                (312.4425354003906, 69.91675567626953),
                (311.38800048828125, 71.7652587890625),
                (310.06976318359375, 73.54772186279297),
                (308.4219665527344, 75.59428405761719),
                (306.57647705078125, 77.17872619628906),
                (304.46728515625, 78.6971206665039),
                (302.0944519042969, 80.21551513671875),
                (299.5898742675781, 81.7339096069336),
                (296.9533996582031, 83.12028503417969),
                (293.92144775390625, 84.63871765136719),
                (291.4168701171875, 85.56293487548828),
                (289.0440368652344, 86.28912353515625),
                (286.67120361328125, 86.81729888916016),
                (284.56207275390625, 87.21337890625),
                (282.518798828125, 87.41143798828125),
                (280.3437194824219, 87.47744750976562),
                (277.4436340332031, 87.47744750976562)
            ])
        ]
    }

    private func deviceCThenDetachedDStrokes() -> [InkStroke] {
        [
            InkStroke(points: [
                InkPoint(x: 210.7413, y: 54.4026, timeOffset: 0),
                InkPoint(x: 208.1048, y: 54.9308, timeOffset: 0.0529),
                InkPoint(x: 205.8639, y: 57.1093, timeOffset: 0.0667),
                InkPoint(x: 200.6568, y: 63.1830, timeOffset: 0.0833),
                InkPoint(x: 195.5157, y: 71.2371, timeOffset: 0.1000),
                InkPoint(x: 193.9339, y: 77.4428, timeOffset: 0.1112),
                InkPoint(x: 194.1316, y: 80.3476, timeOffset: 0.1171),
                InkPoint(x: 208.1707, y: 81.7339, timeOffset: 0.1528),
                InkPoint(x: 216.4097, y: 79.2253, timeOffset: 0.1666),
                InkPoint(x: 218.9802, y: 78.3670, timeOffset: 0.1695)
            ]),
            InkStroke(points: [
                InkPoint(x: 281.7938, y: 60.9384, timeOffset: 0),
                InkPoint(x: 281.2665, y: 73.7458, timeOffset: 0.0557),
                InkPoint(x: 281.2665, y: 76.2545, timeOffset: 0.0642)
            ]),
            InkStroke(points: [
                InkPoint(x: 276.4550, y: 64.1732, timeOffset: 0),
                InkPoint(x: 277.9050, y: 56.7132, timeOffset: 0.0501),
                InkPoint(x: 282.8484, y: 54.6007, timeOffset: 0.0668),
                InkPoint(x: 296.1624, y: 55.9210, timeOffset: 0.1001),
                InkPoint(x: 303.6764, y: 61.1364, timeOffset: 0.1167),
                InkPoint(x: 307.7629, y: 73.4817, timeOffset: 0.1501),
                InkPoint(x: 303.0832, y: 79.0272, timeOffset: 0.1667),
                InkPoint(x: 288.2531, y: 85.3649, timeOffset: 0.2001),
                InkPoint(x: 281.0028, y: 84.7047, timeOffset: 0.2167)
            ])
        ]
    }

    private func repeatDeviceCThenDetachedDStrokes() -> [InkStroke] {
        [
            InkStroke(points: [
                InkPoint(x: 188.1337, y: 54.5346, timeOffset: 0),
                InkPoint(x: 188.1337, y: 52.6201, timeOffset: 0.0059),
                InkPoint(x: 186.42, y: 52.6862, timeOffset: 0.0310),
                InkPoint(x: 183.8494, y: 54.9308, timeOffset: 0.0501),
                InkPoint(x: 182.6631, y: 56.0531, timeOffset: 0.0646),
                InkPoint(x: 181.4107, y: 57.3074, timeOffset: 0.0667),
                InkPoint(x: 180.0925, y: 58.7598, timeOffset: 0.0725),
                InkPoint(x: 178.6425, y: 60.2782, timeOffset: 0.0750),
                InkPoint(x: 177.1924, y: 61.9286, timeOffset: 0.0809),
                InkPoint(x: 175.7423, y: 63.6451, timeOffset: 0.0834),
                InkPoint(x: 174.0946, y: 65.6256, timeOffset: 0.0892),
                InkPoint(x: 172.7763, y: 67.4081, timeOffset: 0.0917),
                InkPoint(x: 171.524, y: 69.3226, timeOffset: 0.0975),
                InkPoint(x: 170.4035, y: 71.3691, timeOffset: 0.1000),
                InkPoint(x: 169.4808, y: 73.3497, timeOffset: 0.1061),
                InkPoint(x: 168.7557, y: 75.3302, timeOffset: 0.1083),
                InkPoint(x: 168.1625, y: 77.4428, timeOffset: 0.1142),
                InkPoint(x: 168.0966, y: 79.0272, timeOffset: 0.1167),
                InkPoint(x: 168.1625, y: 81.7339, timeOffset: 0.1223),
                InkPoint(x: 169.6126, y: 83.8465, timeOffset: 0.1309),
                InkPoint(x: 171.6558, y: 85.2329, timeOffset: 0.1392),
                InkPoint(x: 174.1605, y: 85.827, timeOffset: 0.1477),
                InkPoint(x: 177.1265, y: 86.0911, timeOffset: 0.1556),
                InkPoint(x: 178.9061, y: 86.1571, timeOffset: 0.1641),
                InkPoint(x: 181.8721, y: 86.1571, timeOffset: 0.1668),
                InkPoint(x: 183.454, y: 86.1571, timeOffset: 0.1750),
                InkPoint(x: 184.9699, y: 86.1571, timeOffset: 0.1806),
                InkPoint(x: 186.4859, y: 86.0251, timeOffset: 0.1834)
            ]),
            InkStroke(points: [
                InkPoint(x: 244.4879, y: 59.2219, timeOffset: 0),
                InkPoint(x: 243.7629, y: 63.7111, timeOffset: 0.0357),
                InkPoint(x: 243.7629, y: 70.4449, timeOffset: 0.0523),
                InkPoint(x: 243.7629, y: 78.0369, timeOffset: 0.0664),
                InkPoint(x: 243.4993, y: 86.7513, timeOffset: 0.0833)
            ]),
            InkStroke(points: [
                InkPoint(x: 233.283, y: 57.0433, timeOffset: 0),
                InkPoint(x: 232.8216, y: 54.9308, timeOffset: 0.0058),
                InkPoint(x: 236.974, y: 53.7424, timeOffset: 0.0394),
                InkPoint(x: 245.7402, y: 53.0823, timeOffset: 0.0583),
                InkPoint(x: 257.5384, y: 53.5444, timeOffset: 0.0749),
                InkPoint(x: 266.766, y: 57.5715, timeOffset: 0.0918),
                InkPoint(x: 271.3798, y: 63.249, timeOffset: 0.1084),
                InkPoint(x: 271.2479, y: 70.907, timeOffset: 0.1306),
                InkPoint(x: 267.0296, y: 77.4428, timeOffset: 0.1472),
                InkPoint(x: 258.8566, y: 83.6484, timeOffset: 0.1666),
                InkPoint(x: 248.7722, y: 87.2134, timeOffset: 0.1917),
                InkPoint(x: 244.9493, y: 87.3454, timeOffset: 0.2000)
            ])
        ]
    }
}
