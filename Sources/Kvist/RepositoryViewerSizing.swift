import Foundation

struct RepositoryViewerSizing {
    static let expandedContentWidthKey = "repositoryViewerExpandedContentWidth"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var savedExpandedContentWidth: CGFloat? {
        guard defaults.object(forKey: Self.expandedContentWidthKey) != nil else {
            return nil
        }
        let width = defaults.double(forKey: Self.expandedContentWidthKey)
        guard width.isFinite, width > 0 else { return nil }
        return CGFloat(width)
    }

    func saveExpandedContentWidth(_ width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        defaults.set(Double(width), forKey: Self.expandedContentWidthKey)
    }

    func targetContentWidth(
        currentContentWidth: CGFloat,
        defaultExpandedContentWidth: CGFloat,
        minimumExpandedContentWidth: CGFloat?
    ) -> CGFloat {
        let preferredWidth = savedExpandedContentWidth
            ?? defaultExpandedContentWidth
        return max(
            currentContentWidth,
            preferredWidth,
            minimumExpandedContentWidth ?? 0
        )
    }

    static func manuallyResizedWidth(
        currentContentWidth: CGFloat,
        automaticContentWidth: CGFloat?
    ) -> CGFloat? {
        guard let automaticContentWidth,
              abs(currentContentWidth - automaticContentWidth) > 1
        else {
            return nil
        }
        return currentContentWidth
    }
}
