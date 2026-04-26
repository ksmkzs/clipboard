import Foundation
import Darwin

struct EditorSessionID: Hashable, Equatable {
    let rawValue: String

    init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }
}

enum GlobalTransformFrontmostWindowKind: Equatable {
    case noteEditor
    case standaloneNote
    case panel
    case settings
    case help
    case none
}

struct GlobalTransformRoutingSnapshot: Equatable {
    let appIsActive: Bool
    let frontmostWindowKind: GlobalTransformFrontmostWindowKind
    let activeEditorSessionID: EditorSessionID?
    let frontmostExternalPID: pid_t?
}

struct ExternalSelectionCopySnapshot: Equatable {
    let previousChangeCount: Int
    let currentChangeCount: Int
    let copiedText: String?
}

enum GlobalTransformRoute: Equatable {
    case editor(EditorSessionID)
    case panel
    case externalSelection(pid_t?)
}

enum GlobalTransformRoutingPolicy {
    static func resolve(_ snapshot: GlobalTransformRoutingSnapshot) -> GlobalTransformRoute {
        guard snapshot.appIsActive else {
            return .externalSelection(snapshot.frontmostExternalPID)
        }

        switch snapshot.frontmostWindowKind {
        case .noteEditor, .standaloneNote:
            if let sessionID = snapshot.activeEditorSessionID {
                return .editor(sessionID)
            }
            return .externalSelection(snapshot.frontmostExternalPID)
        case .panel:
            return .panel
        case .settings, .help, .none:
            return .externalSelection(snapshot.frontmostExternalPID)
        }
    }
}

enum GlobalTransformCopyPolicy {
    static func resolvedCopiedText(_ snapshot: ExternalSelectionCopySnapshot) -> String? {
        guard snapshot.currentChangeCount != snapshot.previousChangeCount,
              let copiedText = snapshot.copiedText,
              !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return copiedText
    }
}

final class EditorCommandDispatcher {
    typealias Sink = (EditorCommand, String?) -> Void

    private struct Registration {
        let token: UUID
        let sink: Sink
    }

    private var registrations: [EditorSessionID: Registration] = [:]

    @discardableResult
    func register(sessionID: EditorSessionID, sink: @escaping Sink) -> UUID {
        let token = UUID()
        registrations[sessionID] = Registration(token: token, sink: sink)
        return token
    }

    func unregister(sessionID: EditorSessionID, token: UUID?) {
        guard let token,
              registrations[sessionID]?.token == token else {
            return
        }
        registrations.removeValue(forKey: sessionID)
    }

    @discardableResult
    func dispatch(_ command: EditorCommand, to sessionID: EditorSessionID, payloadText: String? = nil) -> Bool {
        guard let registration = registrations[sessionID] else {
            return false
        }
        registration.sink(command, payloadText)
        return true
    }
}
