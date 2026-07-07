import Foundation
import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var store: ChartLibraryStore
    @State private var projectPath: [ProjectRoute] = []
    @State private var isLaunchAnimationVisible: Bool
    @State private var activeOperationMessage: String?
    @State private var activeOperationID = UUID()

    private static let hasSeenAccountLandingKey = "iChartHasSeenAccountLanding"

    init() {
        _isLaunchAnimationVisible = State(
            initialValue: UserDefaults.standard.bool(forKey: Self.hasSeenAccountLandingKey)
        )
    }

    var body: some View {
        ZStack {
            NavigationStack(path: $projectPath) {
                LibraryView { chartID, initialCanvasMode in
                    guard store.canOpenChartsForEditing else {
                        store.selectedChartID = nil
                        projectPath.removeAll()
                        return
                    }

                    let chartTitle = store.charts.first(where: { $0.id == chartID })?.title ?? "Chart"
                    showAppOperation("Opening \(chartTitle)...")
                    store.selectedChartID = chartID
                    projectPath = [.chart(chartID, initialCanvasMode)]
                }
                .navigationTitle("iChart")
                .navigationDestination(for: ProjectRoute.self) { route in
                    switch route {
                    case .chart(let chartID, let initialCanvasMode):
                        if store.isChartEditingLockedByCurrentPlan {
                            ContentUnavailableView(
                                "Resolve Basic Limit",
                                systemImage: "lock.doc",
                                description: Text("Remove local charts until the library has 3 Basic charts, or restore Pro to keep editing.")
                            )
                        } else if let chart = chartBinding(for: chartID) {
                            EditorView(chart: chart, initialCanvasMode: initialCanvasMode) {
                                store.selectedChartID = nil
                                projectPath.removeAll()
                            }
                        } else {
                            ContentUnavailableView(
                                "Chart Not Found",
                                systemImage: "music.quarternote.3",
                                description: Text("This chart is no longer available in the library.")
                            )
                        }
                    }
                }
                .onChange(of: store.isChartEditingLockedByCurrentPlan) { _, isLocked in
                    guard isLocked else {
                        return
                    }

                    store.selectedChartID = nil
                    projectPath.removeAll()
                }
            }

            if let activeOperationMessage {
                IChartAppOperationOverlay(message: activeOperationMessage)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(0.5)
            }

            if isLaunchAnimationVisible {
                IChartLaunchScreenView(capturedHandwritingSample: launchHandwritingSample) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isLaunchAnimationVisible = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.16), value: activeOperationMessage)
    }

    private var launchHandwritingSample: IChartLaunchHandwritingSample? {
        IChartLaunchHandwritingSample.bundledCanonicalLaunchSample()
    }

    private func showAppOperation(_ message: String) {
        let operationID = UUID()
        activeOperationID = operationID
        activeOperationMessage = message

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard activeOperationID == operationID else {
                return
            }

            activeOperationMessage = nil
        }
    }

    private func chartBinding(for chartID: Chart.ID) -> Binding<Chart>? {
        guard let index = store.charts.firstIndex(where: { $0.id == chartID }) else {
            return nil
        }

        return $store.charts[index]
    }
}

private enum ProjectRoute: Hashable {
    case chart(UUID, EditorCanvasMode)
}

private struct IChartAppOperationOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct IChartLaunchScreenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let capturedHandwritingSample: IChartLaunchHandwritingSample?
    let onFinished: () -> Void

    @State private var didStartAnimation = false
    @State private var foundationOpacity: Double = 0
    @State private var handwrittenLetterProgress: CGFloat = 0
    @State private var handwrittenOpacity: Double = 0
    @State private var handwrittenScale: CGFloat = 0.98
    @State private var staffLockProgress: Double = 0
    @State private var resolvedCOpacity: Double = 0
    @State private var resolvedHartOpacity: Double = 0
    @State private var resolvedLogoScale: CGFloat = 0.94
    @State private var screenOpacity: Double = 1

    var body: some View {
        GeometryReader { geometry in
            let logoSize = min(max(geometry.size.width * 0.16, 118), 190)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.08, blue: 0.11),
                        Color(red: 0.03, green: 0.05, blue: 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                IChartLaunchWordmarkStageView(
                    size: logoSize,
                    capturedHandwritingSample: capturedHandwritingSample,
                    foundationOpacity: foundationOpacity,
                    handwrittenLetterProgress: handwrittenLetterProgress,
                    handwrittenOpacity: handwrittenOpacity,
                    handwrittenScale: handwrittenScale,
                    staffLockProgress: staffLockProgress,
                    resolvedCOpacity: resolvedCOpacity,
                    resolvedHartOpacity: resolvedHartOpacity,
                    resolvedLogoScale: resolvedLogoScale
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 40)
            }
            .opacity(screenOpacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("iChart")
        .task {
            await runAnimationIfNeeded()
        }
    }

    @MainActor
    private func runAnimationIfNeeded() async {
        guard !didStartAnimation else {
            return
        }

        didStartAnimation = true

        if reduceMotion {
            foundationOpacity = 1
            handwrittenLetterProgress = 1
            handwrittenOpacity = 0
            handwrittenScale = 1
            staffLockProgress = 0
            resolvedCOpacity = 1
            resolvedHartOpacity = 1
            resolvedLogoScale = 1
            try? await Task.sleep(nanoseconds: 650_000_000)
            withAnimation(.easeOut(duration: 0.20)) {
                screenOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            onFinished()
            return
        }

        try? await Task.sleep(nanoseconds: 240_000_000)

        withAnimation(.easeInOut(duration: 1.05)) {
            foundationOpacity = 1
        }

        try? await Task.sleep(nanoseconds: 1_120_000_000)

        withAnimation(.easeOut(duration: 0.28)) {
            handwrittenOpacity = 1
        }

        withAnimation(.linear(duration: 2.42)) {
            handwrittenLetterProgress = 1
        }

        try? await Task.sleep(nanoseconds: 2_580_000_000)

        withAnimation(.easeInOut(duration: 0.24)) {
            staffLockProgress = 1
            resolvedLogoScale = 1.018
        }

        try? await Task.sleep(nanoseconds: 220_000_000)

        withAnimation(.easeOut(duration: 0.16)) {
            handwrittenOpacity = 0
            handwrittenScale = 1.035
        }

        withAnimation(.easeOut(duration: 0.34)) {
            resolvedCOpacity = 1
            resolvedHartOpacity = 1
            resolvedLogoScale = 1
        }

        try? await Task.sleep(nanoseconds: 280_000_000)

        withAnimation(.easeOut(duration: 0.58)) {
            staffLockProgress = 0
        }

        try? await Task.sleep(nanoseconds: 1_420_000_000)

        withAnimation(.easeOut(duration: 0.46)) {
            screenOpacity = 0
        }

        try? await Task.sleep(nanoseconds: 500_000_000)
        onFinished()
    }
}

private struct IChartLaunchWordmarkStageView: View {
    let size: CGFloat
    let capturedHandwritingSample: IChartLaunchHandwritingSample?
    let foundationOpacity: Double
    let handwrittenLetterProgress: CGFloat
    let handwrittenOpacity: Double
    let handwrittenScale: CGFloat
    let staffLockProgress: Double
    let resolvedCOpacity: Double
    let resolvedHartOpacity: Double
    let resolvedLogoScale: CGFloat

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("i")
                .font(.custom("FinaleMaestroText-Italic", size: size * 0.58))
                .foregroundStyle(paper)
                .padding(.trailing, size * -0.025)
                .offset(x: size * -0.055)
                .opacity(foundationOpacity)

            staffWord
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityLabel("iChart")
    }

    private var staffWord: some View {
        resolvedWord
            .overlay(alignment: .leading) {
                handwrittenWord
                    .opacity(handwrittenOpacity)
                    .scaleEffect(handwrittenScale, anchor: .leading)
            }
            .padding(.trailing, size * 0.14)
            .overlay {
                IChartLaunchStaffMeasureLines(lockProgress: staffLockProgress)
                    .frame(height: size * 0.72)
                    .padding(.top, size * 0.08)
                    .opacity(foundationOpacity)
                    .allowsHitTesting(false)
            }
            .scaleEffect(resolvedLogoScale)
    }

    private var resolvedWord: some View {
        HStack(alignment: .lastTextBaseline, spacing: -size * 0.035) {
            Text("C")
                .font(.custom("FinaleMaestroText", size: size))
                .foregroundStyle(logoBlue)
                .opacity(resolvedCOpacity)

            Text("hart")
                .font(.custom("FinaleMaestroText", size: size * 0.74))
                .foregroundStyle(paper)
                .baselineOffset(size * 0.01)
                .opacity(resolvedHartOpacity)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var handwrittenWord: some View {
        Group {
            if let capturedHandwritingSample {
                IChartLaunchCapturedHandwritingView(
                    sample: capturedHandwritingSample,
                    size: size,
                    progress: handwrittenLetterProgress,
                    color: paper
                )
            }
        }
        .offset(x: size * 0.02, y: size * 0.10)
    }

    private var paper: Color {
        Color(red: 0.97, green: 0.95, blue: 0.92)
    }

    private var logoBlue: Color {
        Color(red: 0.56, green: 0.83, blue: 0.90)
    }
}

struct IChartLaunchHandwritingSample: Codable, Equatable {
    private static let canonicalResourceName = "IChartCanonicalLaunchHandwriting"
    private static let canonicalResourceSubdirectory = "Launch"
    private static let cachedCanonicalLaunchSample = loadBundledCanonicalLaunchSample(bundle: .main)

    var strokes: [Stroke]

    var isDrawable: Bool {
        strokes.contains { $0.points.count > 1 }
    }

    static func bundledCanonicalLaunchSample(bundle: Bundle = .main) -> IChartLaunchHandwritingSample? {
        if bundle === Bundle.main {
            return cachedCanonicalLaunchSample
        }

        return loadBundledCanonicalLaunchSample(bundle: bundle)
    }

    private static func loadBundledCanonicalLaunchSample(bundle: Bundle) -> IChartLaunchHandwritingSample? {
        let url = bundle.url(
            forResource: canonicalResourceName,
            withExtension: "json",
            subdirectory: canonicalResourceSubdirectory
        ) ?? bundle.url(
            forResource: canonicalResourceName,
            withExtension: "json"
        )

        guard let url,
              let data = try? Data(contentsOf: url),
              let sample = try? JSONDecoder().decode(IChartLaunchHandwritingSample.self, from: data),
              sample.isDrawable else {
            return nil
        }

        return sample
    }

    struct Stroke: Codable, Equatable {
        var points: [Point]
    }

    struct Point: Codable, Equatable {
        var x: Double
        var y: Double
        var time: Double
    }
}

private struct IChartLaunchCapturedHandwritingView: View {
    let sample: IChartLaunchHandwritingSample
    let size: CGFloat
    let progress: CGFloat
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(sample.strokes.indices, id: \.self) { index in
                IChartLaunchCapturedHandwritingStrokeShape(
                    points: sample.strokes[index].points,
                    progress: progress
                )
                .stroke(
                    color.opacity(0.98),
                    style: StrokeStyle(
                        lineWidth: size * 0.036,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .frame(width: size * 2.04, height: size * 0.76, alignment: .topLeading)
    }
}

private struct IChartLaunchCapturedHandwritingStrokeShape: Shape {
    let points: [IChartLaunchHandwritingSample.Point]
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard let firstPoint = points.first,
              progress >= CGFloat(firstPoint.time) else {
            return Path()
        }

        var path = Path()
        path.move(to: point(firstPoint, in: rect))

        for index in points.indices.dropFirst() {
            let previousPoint = points[points.index(before: index)]
            let nextPoint = points[index]
            let previousTime = CGFloat(previousPoint.time)
            let nextTime = CGFloat(nextPoint.time)

            if nextTime <= progress {
                path.addLine(to: point(nextPoint, in: rect))
            } else if progress > previousTime {
                path.addLine(to: interpolatedPoint(
                    from: previousPoint,
                    to: nextPoint,
                    progress: progress,
                    in: rect
                ))
                break
            } else {
                break
            }
        }

        return path
    }

    private func point(_ point: IChartLaunchHandwritingSample.Point, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * CGFloat(point.x),
            y: rect.minY + rect.height * CGFloat(point.y)
        )
    }

    private func interpolatedPoint(
        from start: IChartLaunchHandwritingSample.Point,
        to end: IChartLaunchHandwritingSample.Point,
        progress: CGFloat,
        in rect: CGRect
    ) -> CGPoint {
        let startTime = CGFloat(start.time)
        let endTime = CGFloat(end.time)
        let timeRange = max(endTime - startTime, 0.0001)
        let amount = min(max((progress - startTime) / timeRange, 0), 1)
        let x = CGFloat(start.x) + (CGFloat(end.x) - CGFloat(start.x)) * amount
        let y = CGFloat(start.y) + (CGFloat(end.y) - CGFloat(start.y)) * amount
        return CGPoint(
            x: rect.minX + rect.width * x,
            y: rect.minY + rect.height * y
        )
    }
}

private struct IChartLaunchStaffMeasureLines: View {
    let lockProgress: Double

    var body: some View {
        GeometryReader { geometry in
            let lockAmount = min(max(lockProgress, 0), 1)
            let lineWidth = max(geometry.size.height * 0.018, 1) * (1 + CGFloat(lockAmount) * 0.08)
            let lineOpacity = 0.23 + lockAmount * 0.13
            let barOpacity = 0.24 + lockAmount * 0.16
            let barSpacing = max(geometry.size.width * 0.024, 4)

            Path { path in
                for index in 0..<5 {
                    let y = geometry.size.height * CGFloat(index) / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(
                Color.white.opacity(lineOpacity),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )

            Path { path in
                let firstBarX = geometry.size.width - barSpacing
                path.move(to: CGPoint(x: firstBarX, y: 0))
                path.addLine(to: CGPoint(x: firstBarX, y: geometry.size.height))
                path.move(to: CGPoint(x: geometry.size.width, y: 0))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
            }
            .stroke(
                Color.white.opacity(barOpacity),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )
        }
    }
}
