//
//  Element+TypeChecking.swift
//  AXorcist
//
//  Convenience methods for checking element types and roles
//

import ApplicationServices
import Foundation

// MARK: - Role Constants

extension Element {
    /// Common accessibility role constants
    public enum Roles {
        public static let application = "AXApplication"
        public static let window = "AXWindow"
        public static let button = "AXButton"
        public static let textField = "AXTextField"
        public static let textArea = "AXTextArea"
        public static let staticText = "AXStaticText"
        public static let link = "AXLink"
        public static let image = "AXImage"
        public static let menuBar = "AXMenuBar"
        public static let menu = "AXMenu"
        public static let menuItem = "AXMenuItem"
        public static let menuButton = "AXMenuButton"
        public static let popUpButton = "AXPopUpButton"
        public static let checkBox = "AXCheckBox"
        public static let radioButton = "AXRadioButton"
        public static let comboBox = "AXComboBox"
        public static let list = "AXList"
        public static let table = "AXTable"
        public static let outline = "AXOutline"
        public static let row = "AXRow"
        public static let column = "AXColumn"
        public static let cell = "AXCell"
        public static let scrollArea = "AXScrollArea"
        public static let scrollBar = "AXScrollBar"
        public static let slider = "AXSlider"
        public static let progressIndicator = "AXProgressIndicator"
        public static let group = "AXGroup"
        public static let tabGroup = "AXTabGroup"
        public static let toolbar = "AXToolbar"
        public static let unknown = "AXUnknown"
    }

    /// Common accessibility subrole constants
    public enum Subroles {
        public static let dialog = "AXDialog"
        public static let systemDialog = "AXSystemDialog"
        public static let floatingWindow = "AXFloatingWindow"
        public static let standardWindow = "AXStandardWindow"
        public static let closeButton = "AXCloseButton"
        public static let minimizeButton = "AXMinimizeButton"
        public static let zoomButton = "AXZoomButton"
        public static let fullScreenButton = "AXFullScreenButton"
        public static let secureTextField = "AXSecureTextField"
        public static let searchField = "AXSearchField"
        public static let applicationDockItem = "AXApplicationDockItem"
        public static let folderDockItem = "AXFolderDockItem"
        public static let fileDockItem = "AXFileDockItem"
        public static let urlDockItem = "AXURLDockItem"
        public static let minimizedWindowDockItem = "AXMinimizedWindowDockItem"
        public static let separator = "AXSeparator"
        public static let separatorMenuItem = "AXSeparatorMenuItem"
    }
}

// MARK: - Type Checking Methods

extension Element {
    // MARK: - Window Types

    // Note: isWindow is already defined as a computed property in Element+WindowOperations.swift

    /// Check if element is a dialog window
    @MainActor
    public func isDialog() -> Bool {
        role() == Roles.window && (subrole() == Subroles.dialog || subrole() == Subroles.systemDialog)
    }

    /// Check if element is a standard window (not floating, dialog, etc.)
    @MainActor
    public func isStandardWindow() -> Bool {
        role() == Roles.window && subrole() == Subroles.standardWindow
    }

    // MARK: - Control Types

    /// Check if element is a button
    @MainActor
    public func isButton() -> Bool {
        role() == Roles.button
    }

    /// Check if element is a text field
    @MainActor
    public func isTextField() -> Bool {
        role() == Roles.textField
    }

    /// Check if element is a secure text field (password field)
    @MainActor
    public func isSecureTextField() -> Bool {
        role() == Roles.textField && subrole() == Subroles.secureTextField
    }

    /// Check if element is a search field
    @MainActor
    public func isSearchField() -> Bool {
        role() == Roles.textField && subrole() == Subroles.searchField
    }

    /// Check if element is a text area
    @MainActor
    public func isTextArea() -> Bool {
        role() == Roles.textArea
    }

    /// Check if element is any kind of text input (field or area)
    @MainActor
    public func isTextInput() -> Bool {
        self.isTextField() || self.isTextArea()
    }

    /// Check if element is static text
    @MainActor
    public func isStaticText() -> Bool {
        role() == Roles.staticText
    }

    /// Check if element is a link
    @MainActor
    public func isLink() -> Bool {
        role() == Roles.link
    }

    /// Check if element is a checkbox
    @MainActor
    public func isCheckBox() -> Bool {
        role() == Roles.checkBox
    }

    /// Check if element is a radio button
    @MainActor
    public func isRadioButton() -> Bool {
        role() == Roles.radioButton
    }

    /// Check if element is a combo box
    @MainActor
    public func isComboBox() -> Bool {
        role() == Roles.comboBox
    }

    /// Check if element is a popup button
    @MainActor
    public func isPopUpButton() -> Bool {
        role() == Roles.popUpButton
    }

    /// Check if element is a slider
    @MainActor
    public func isSlider() -> Bool {
        role() == Roles.slider
    }

    // MARK: - Menu Types

    /// Check if element is a menu
    @MainActor
    public func isMenu() -> Bool {
        role() == Roles.menu
    }

    /// Check if element is a menu item
    @MainActor
    public func isMenuItem() -> Bool {
        role() == Roles.menuItem
    }

    /// Check if element is a separator menu item
    @MainActor
    public func isSeparatorMenuItem() -> Bool {
        role() == Roles.menuItem && subrole() == Subroles.separatorMenuItem
    }

    /// Check if element is a menu bar
    @MainActor
    public func isMenuBar() -> Bool {
        role() == Roles.menuBar
    }

    /// Check if element is a menu button
    @MainActor
    public func isMenuButton() -> Bool {
        role() == Roles.menuButton
    }

    // MARK: - Container Types

    /// Check if element is a scroll area
    @MainActor
    public func isScrollArea() -> Bool {
        role() == Roles.scrollArea
    }

    /// Check if element is a scroll bar
    @MainActor
    public func isScrollBar() -> Bool {
        role() == Roles.scrollBar
    }

    /// Check if element is a list
    @MainActor
    public func isList() -> Bool {
        role() == Roles.list
    }

    /// Check if element is a table
    @MainActor
    public func isTable() -> Bool {
        role() == Roles.table
    }

    /// Check if element is an outline
    @MainActor
    public func isOutline() -> Bool {
        role() == Roles.outline
    }

    /// Check if element is a group
    @MainActor
    public func isGroup() -> Bool {
        role() == Roles.group
    }

    /// Check if element is a tab group
    @MainActor
    public func isTabGroup() -> Bool {
        role() == Roles.tabGroup
    }

    // MARK: - Application Types

    // Note: isApplication is already defined as a computed property in Element+WindowOperations.swift

    // MARK: - Dock Item Types

    /// Check if element is any kind of dock item
    @MainActor
    public func isDockItem() -> Bool {
        let sub = subrole()
        return sub == Subroles.applicationDockItem ||
            sub == Subroles.folderDockItem ||
            sub == Subroles.fileDockItem ||
            sub == Subroles.urlDockItem ||
            sub == Subroles.minimizedWindowDockItem
    }

    /// Check if element is a separator (in dock or elsewhere)
    @MainActor
    public func isSeparator() -> Bool {
        role() == Subroles.separator || subrole() == Subroles.separator
    }

    // MARK: - State Checking

    /// Check if element is interactive (can be clicked, typed into, etc.)
    @MainActor
    public func isInteractive() -> Bool {
        // Check if enabled
        guard isEnabled() != false else { return false }

        // Check common interactive roles
        let interactiveRoles = [
            Roles.button,
            Roles.textField,
            Roles.textArea,
            Roles.link,
            Roles.checkBox,
            Roles.radioButton,
            Roles.comboBox,
            Roles.popUpButton,
            Roles.menuItem,
            Roles.menuButton,
            Roles.slider,
        ]

        if let currentRole = role(), interactiveRoles.contains(currentRole) {
            return true
        }

        // Check if it has press action
        if let actions = supportedActions(), actions.contains("AXPress") {
            return true
        }

        return false
    }

    /// Check if element can contain text input
    @MainActor
    public func canAcceptTextInput() -> Bool {
        self.isTextInput() && isEnabled() != false
    }

    /// Check if element is scrollable (has scroll bars or is a scroll area)
    @MainActor
    public func isScrollable() -> Bool {
        if self.isScrollArea() { return true }

        // Check if it has scroll bars
        if horizontalScrollBar() != nil || verticalScrollBar() != nil {
            return true
        }

        return false
    }
}
