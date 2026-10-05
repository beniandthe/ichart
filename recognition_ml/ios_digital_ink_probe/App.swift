import UIKit

@main
final class ProbeApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let label = UILabel(frame: CGRect(x: 40, y: 120, width: 600, height: 180))
        label.numberOfLines = 0
        label.text = "Developer handwriting comparison\n\nThis separate test app does not open or change your iChart charts."
        controller.view.addSubview(label)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        if ProcessInfo.processInfo.arguments.contains("--run-ink-probe") {
            Task { @MainActor in
                do {
                    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    try await ProbeEngine.run(folder: folder) { label.text = $0 }
                } catch {
                    label.text = "Comparison did not finish: \(error.localizedDescription)"
                    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let report: [String: Any] = ["complete": false, "error": error.localizedDescription]
                    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                        try? data.write(to: folder.appendingPathComponent("probe-report.json"), options: .atomic)
                    }
                }
            }
        }
        return true
    }
}
