import Foundation

struct ChordEntryDiagnosticCoverageReport: Equatable {
    var chartID: UUID
    var chartTitle: String
    var renderedChordEventIDs: [UUID]
    var loggedChordEventIDs: [UUID]
    var missingChordEventIDs: [UUID]
    var staleChordEventIDs: [UUID]
    var resolutionCounts: [ChordEntryDiagnosticResolution: Int]

    var isComplete: Bool {
        missingChordEventIDs.isEmpty
    }
}

enum ChordEntryDiagnosticCoverage {
    static func report(
        for chart: Chart,
        events: [ChordEntryDiagnosticEvent]
    ) -> ChordEntryDiagnosticCoverageReport {
        let chartEvents = chart.systems
            .flatMap(\.measures)
            .flatMap(\.chordEvents)
        let renderedChordEventIDs = chartEvents.map(\.id)
        let renderedChordEventIDSet = Set(renderedChordEventIDs)

        let chartDiagnostics = events.filter { event in
            event.chartID == chart.id
        }
        let loggedChordEventIDs = chartDiagnostics
            .compactMap(\.chordEventID)
            .uniquedPreservingOrder()
        let loggedChordEventIDSet = Set(loggedChordEventIDs)
        let missingChordEventIDs = renderedChordEventIDs.filter { chordEventID in
            !loggedChordEventIDSet.contains(chordEventID)
        }
        let staleChordEventIDs = loggedChordEventIDs.filter { chordEventID in
            !renderedChordEventIDSet.contains(chordEventID)
        }
        let resolutionCounts = chartDiagnostics.reduce(into: [ChordEntryDiagnosticResolution: Int]()) { counts, event in
            counts[event.resolution, default: 0] += 1
        }

        return ChordEntryDiagnosticCoverageReport(
            chartID: chart.id,
            chartTitle: chart.title,
            renderedChordEventIDs: renderedChordEventIDs,
            loggedChordEventIDs: loggedChordEventIDs,
            missingChordEventIDs: missingChordEventIDs,
            staleChordEventIDs: staleChordEventIDs,
            resolutionCounts: resolutionCounts
        )
    }
}

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        return filter { element in
            seen.insert(element).inserted
        }
    }
}
