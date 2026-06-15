import AppKit
import Foundation

enum AppPreferences {
    static let didChangeNotification = Notification.Name("CloseYourLaptopPreferencesDidChange")

    private static let monitoringEnabledKey = "monitoringEnabled"
    private static let menuBarIconSizeKey = "menuBarIconSize"
    private static let showMenuBarStatusTextKey = "showMenuBarStatusText"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            monitoringEnabledKey: true,
            menuBarIconSizeKey: MenuBarIconSize.regular.rawValue,
            showMenuBarStatusTextKey: true
        ])
    }

    static var monitoringEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: monitoringEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: monitoringEnabledKey) }
    }

    static var menuBarIconSize: MenuBarIconSize {
        get {
            let rawValue = UserDefaults.standard.string(forKey: menuBarIconSizeKey)
            return rawValue.flatMap(MenuBarIconSize.init(rawValue:)) ?? .regular
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: menuBarIconSizeKey) }
    }

    static var showMenuBarStatusText: Bool {
        get { UserDefaults.standard.bool(forKey: showMenuBarStatusTextKey) }
        set { UserDefaults.standard.set(newValue, forKey: showMenuBarStatusTextKey) }
    }
}

enum MenuBarIconSize: String, CaseIterable {
    case regular
    case small

    var displayName: String {
        switch self {
        case .regular:
            return "Regular"
        case .small:
            return "Small"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .regular:
            return 16
        case .small:
            return 13
        }
    }
}
