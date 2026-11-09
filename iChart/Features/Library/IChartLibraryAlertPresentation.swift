import Foundation

/// One stable presenter for the library. A dismissal belongs to the item that
/// was on screen, even if another row has already requested a confirmation.
struct IChartLibraryAlertPresentation {
    enum Item: Identifiable, Equatable {
        case deletion(IChartLibraryDeleteRequest)
        case failure(id: UUID, message: String)

        var id: UUID {
            switch self {
            case .deletion(let request): request.id
            case .failure(let id, _): id
            }
        }
    }

    private(set) var item: Item?

    mutating func requestDeletion(_ request: IChartLibraryDeleteRequest) {
        guard !request.ids.isEmpty else { return }
        item = .deletion(request)
    }

    mutating func presentFailure(_ message: String) {
        item = .failure(id: UUID(), message: message)
    }

    mutating func dismiss(id: UUID?) {
        guard item?.id == id else { return }
        item = nil
    }
}
