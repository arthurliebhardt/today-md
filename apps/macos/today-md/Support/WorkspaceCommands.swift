import SwiftUI

struct WorkspaceCommandActions {
    let canCreateTask: Bool
    let canMarkTasksDone: Bool
    let createTask: () -> Void
    let markTasksDone: () -> Void
}

private struct WorkspaceCommandActionsKey: FocusedValueKey {
    typealias Value = WorkspaceCommandActions
}

extension FocusedValues {
    var workspaceCommandActions: WorkspaceCommandActions? {
        get { self[WorkspaceCommandActionsKey.self] }
        set { self[WorkspaceCommandActionsKey.self] = newValue }
    }
}

struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspaceCommandActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                actions?.createTask()
            }
            .keyboardShortcut("n")
            .disabled(actions?.canCreateTask != true)
        }

        CommandMenu("Task") {
            Button("Mark Selected Tasks Done") {
                actions?.markTasksDone()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(actions?.canMarkTasksDone != true)
        }
    }
}
