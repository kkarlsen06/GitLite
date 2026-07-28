import AppKit
import SwiftUI

enum AppDialogActionRole {
    case primary
    case secondary
    case destructive
    case cancel
}

struct AppDialogAction {
    let title: String
    let role: AppDialogActionRole
}

struct AppDialogDisclosure {
    let title: String
    let summary: String
    let text: String
}

struct AppDialogField {
    let label: String
    let placeholder: String
    let isRequired: Bool

    init(label: String, placeholder: String, isRequired: Bool = true) {
        self.label = label
        self.placeholder = placeholder
        self.isRequired = isRequired
    }
}

struct AppDialogResult {
    let actionIndex: Int?
    let values: [String]
}

@MainActor
enum AppDialog {
    static func run(
        title: String,
        message: String,
        fields: [AppDialogField] = [],
        disclosure: AppDialogDisclosure? = nil,
        actions: [AppDialogAction]
    ) -> AppDialogResult {
        if let disclosure {
            return runDisclosureAlert(
                title: title,
                message: message,
                disclosure: disclosure,
                actions: actions
            )
        }
        return runAlert(
            title: title,
            message: message,
            fields: fields,
            actions: actions
        )
    }

    private static func runAlert(
        title: String,
        message: String,
        fields: [AppDialogField],
        actions: [AppDialogAction]
    ) -> AppDialogResult {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let textFields = fields.map { field in
            let textField = NSTextField()
            textField.placeholderString = field.placeholder
            textField.setAccessibilityLabel(field.label)
            return textField
        }
        if !textFields.isEmpty {
            let rows = zip(fields, textFields).map { field, textField in
                let label = NSTextField(labelWithString: field.label)
                label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                textField.widthAnchor.constraint(equalToConstant: 360).isActive = true
                let row = NSStackView(views: [label, textField])
                row.orientation = .vertical
                row.alignment = .leading
                row.spacing = 4
                return row
            }
            let stack = NSStackView(views: rows)
            stack.orientation = .vertical
            stack.spacing = 10
            stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 4, right: 0)
            stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
            alert.accessoryView = stack
        }

        let orderedActions = actions.enumerated().sorted {
            actionPriority($0.element.role) < actionPriority($1.element.role)
        }
        for (_, action) in orderedActions {
            let button = alert.addButton(withTitle: action.title)
            switch action.role {
            case .primary:
                button.keyEquivalent = "\r"
            case .cancel:
                button.keyEquivalent = "\u{1b}"
            case .secondary, .destructive:
                button.keyEquivalent = ""
            }
        }

        alert.window.initialFirstResponder = textFields.first
        let response = alert.runModal()
        let responseIndex = response.rawValue
            - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let actionIndex = orderedActions.indices.contains(responseIndex)
            ? orderedActions[responseIndex].offset
            : nil
        let values = textFields.map {
            $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let actionIndex,
           actions[actionIndex].role == .primary,
           fields.indices.contains(where: { fields[$0].isRequired && values[$0].isEmpty }) {
            return AppDialogResult(actionIndex: nil, values: values)
        }
        return AppDialogResult(
            actionIndex: actionIndex,
            values: values
        )
    }

    private static func runDisclosureAlert(
        title: String,
        message: String,
        disclosure: AppDialogDisclosure,
        actions: [AppDialogAction]
    ) -> AppDialogResult {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.accessoryView = AppDialogDisclosureAccessoryView(
            disclosure: disclosure
        )

        let orderedActions = actions.enumerated().sorted {
            actionPriority($0.element.role) < actionPriority($1.element.role)
        }
        for (_, action) in orderedActions {
            let button = alert.addButton(withTitle: action.title)
            switch action.role {
            case .primary:
                button.keyEquivalent = "\r"
            case .cancel:
                button.keyEquivalent = "\u{1b}"
            case .secondary, .destructive:
                break
            }
        }

        let response = alert.runModal()
        let responseIndex = response.rawValue
            - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let actionIndex = orderedActions.indices.contains(responseIndex)
            ? orderedActions[responseIndex].offset
            : nil
        return AppDialogResult(actionIndex: actionIndex, values: [])
    }

    private static func actionPriority(_ role: AppDialogActionRole) -> Int {
        switch role {
        case .primary: return 0
        case .destructive: return 1
        case .secondary: return 2
        case .cancel: return 3
        }
    }

    static func message(title: String, message: String, details: String? = nil) {
        let actions = details == nil
            ? [AppDialogAction(title: "OK", role: .primary)]
            : [
                AppDialogAction(title: "Show Details", role: .secondary),
                AppDialogAction(title: "OK", role: .primary)
            ]
        let result = run(
            title: title,
            message: message,
            actions: actions
        )
        guard result.actionIndex == 0, let details else { return }
        let detailsResult = run(
            title: "\(title) Details",
            message: details,
            actions: [
                AppDialogAction(title: "Copy Details", role: .secondary),
                AppDialogAction(title: "OK", role: .primary)
            ]
        )
        guard detailsResult.actionIndex == 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
    }

}

@MainActor
private final class AppDialogDisclosureAccessoryView: NSView {
    private let disclosure: AppDialogDisclosure
    private let disclosureButton: NSButton
    private let diffView: NSHostingView<AnyView>
    private var isExpanded = false

    init(disclosure: AppDialogDisclosure) {
        self.disclosure = disclosure
        disclosureButton = NSButton(
            title: "Show \(disclosure.title)  \(disclosure.summary)",
            target: nil,
            action: nil
        )
        diffView = NSHostingView(rootView: AnyView(
            DiffDocument(text: disclosure.text)
                .preferredColorScheme(.dark)
        ))
        super.init(frame: NSRect(origin: .zero, size: Self.collapsedSize))

        disclosureButton.target = self
        disclosureButton.action = #selector(toggleDisclosure)
        disclosureButton.isBordered = false
        disclosureButton.alignment = .left
        disclosureButton.imagePosition = .imageLeading
        disclosureButton.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: nil
        )
        disclosureButton.font = .systemFont(ofSize: 12, weight: .medium)
        disclosureButton.contentTintColor = .secondaryLabelColor
        disclosureButton.setAccessibilityLabel("Show \(disclosure.title)")
        addSubview(disclosureButton)

        diffView.isHidden = true
        diffView.wantsLayer = true
        diffView.layer?.cornerRadius = 5
        diffView.layer?.masksToBounds = true
        diffView.setAccessibilityLabel("Unsaved changes diff")
        addSubview(diffView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        isExpanded ? Self.expandedSize : Self.collapsedSize
    }

    override func layout() {
        super.layout()
        disclosureButton.frame = NSRect(
            x: 0,
            y: bounds.height - Self.buttonHeight,
            width: bounds.width,
            height: Self.buttonHeight
        )
        diffView.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(0, bounds.height - Self.buttonHeight - 8)
        )
    }

    @objc
    private func toggleDisclosure() {
        let oldHeight = intrinsicContentSize.height
        isExpanded.toggle()
        disclosureButton.state = isExpanded ? .on : .off
        disclosureButton.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        disclosureButton.title = isExpanded
            ? "Hide \(disclosure.title)  \(disclosure.summary)"
            : "Show \(disclosure.title)  \(disclosure.summary)"
        disclosureButton.setAccessibilityLabel(
            isExpanded
                ? "Hide \(disclosure.title)"
                : "Show \(disclosure.title)"
        )
        diffView.isHidden = !isExpanded

        let newSize = intrinsicContentSize
        frame.size = newSize
        invalidateIntrinsicContentSize()
        needsLayout = true
        layoutSubtreeIfNeeded()

        guard let window else { return }
        var windowFrame = window.frame
        let heightChange = newSize.height - oldHeight
        windowFrame.origin.y -= heightChange
        windowFrame.size.height += heightChange
        window.setFrame(windowFrame, display: true, animate: true)
    }

    private static let buttonHeight: CGFloat = 24
    private static let collapsedSize = NSSize(width: 500, height: buttonHeight)
    private static let expandedSize = NSSize(width: 500, height: 300)
}
