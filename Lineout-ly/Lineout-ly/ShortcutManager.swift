//
//  ShortcutManager.swift
//  Lineout-ly
//
//  Created by Andriy on 29/01/2026.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Shortcut Binding Model

/// A keyboard shortcut binding: key identifier + modifier flags.
/// Cross-platform: stored as strings for iCloud sync between macOS and iOS.
struct ShortcutBinding: Codable, Equatable {
    let keyIdentifier: String   // Cross-platform key name: "upArrow", "leftArrow", "a", "tab", etc.
    let command: Bool
    let shift: Bool
    let option: Bool
    let control: Bool

    /// Human-readable display string with modifier symbols (e.g., "⌃⌘↑")
    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option  { parts.append("⌥") }
        if shift   { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(Self.keyDisplayName(for: keyIdentifier))
        return parts.joined()
    }

    /// Human-readable display name for a key identifier.
    static func keyDisplayName(for keyIdentifier: String) -> String {
        switch keyIdentifier {
        case "upArrow":    return "↑"
        case "downArrow":  return "↓"
        case "leftArrow":  return "←"
        case "rightArrow": return "→"
        case "tab":        return "⇥"
        case "return":     return "↩"
        case "delete":     return "⌫"
        case "escape":     return "⎋"
        case "space":      return "␣"
        case "period":     return "."
        case "comma":      return ","
        case "openBracket":  return "["
        case "closeBracket": return "]"
        case "slash":      return "/"
        case "backslash":  return "\\"
        case "minus":      return "-"
        case "equal":      return "="
        case "semicolon":  return ";"
        case "quote":      return "'"
        case "grave":      return "`"
        default:
            return keyIdentifier.uppercased()
        }
    }
}

// MARK: - Customizable Action Definition

/// Defines a customizable shortcut action with display metadata.
struct ShortcutActionInfo {
    let name: String         // Internal action name (matches OutlineAction case)
    let displayName: String  // Human-readable name
    let category: String     // Grouping category
    let defaultBinding: ShortcutBinding
}

// MARK: - Shortcut Manager

/// Manages customizable keyboard shortcuts with iCloud sync.
@Observable
@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()

    /// Custom bindings set by the user (action name → binding). Only non-default entries stored.
    private(set) var customBindings: [String: ShortcutBinding] = [:]

    /// Cached reverse lookup: (keyId, modifiers) → action name
    private var reverseLookup: [String: String] = [:]

    private init() {
        loadFromSettings()
        rebuildReverseLookup()
    }

    // MARK: - Action Definitions

    /// All customizable actions with their default bindings.
    static let actionDefinitions: [ShortcutActionInfo] = [
        // Navigation
        ShortcutActionInfo(name: "collapse",             displayName: "Collapse",                category: "Navigation", defaultBinding: ShortcutBinding(keyIdentifier: "leftArrow",  command: true,  shift: false, option: true,  control: false)),
        ShortcutActionInfo(name: "expand",               displayName: "Expand",                  category: "Navigation", defaultBinding: ShortcutBinding(keyIdentifier: "rightArrow", command: true,  shift: false, option: true,  control: false)),
        ShortcutActionInfo(name: "collapseAll",          displayName: "Collapse All Children",   category: "Navigation", defaultBinding: ShortcutBinding(keyIdentifier: "leftArrow",  command: true,  shift: true,  option: true,  control: false)),
        ShortcutActionInfo(name: "expandAll",            displayName: "Expand All Children",     category: "Navigation", defaultBinding: ShortcutBinding(keyIdentifier: "rightArrow", command: true,  shift: true,  option: true,  control: false)),
        ShortcutActionInfo(name: "zoomIn",               displayName: "Zoom In",                 category: "Navigation", defaultBinding: ShortcutBinding(keyIdentifier: "period",     command: true,  shift: true,  option: false, control: false)),
        ShortcutActionInfo(name: "zoomOut",              displayName: "Zoom Out",                category: "Navigation", defaultBinding: ShortcutBinding(keyIdentifier: "comma",      command: true,  shift: true,  option: false, control: false)),
        ShortcutActionInfo(name: "zoomToRoot",           displayName: "Zoom Home",               category: "Navigation", defaultBinding: ShortcutBinding(keyIdentifier: "escape",     command: false, shift: false, option: false, control: false)),
        ShortcutActionInfo(name: "goHomeAndCollapseAll", displayName: "Go Home & Collapse All",  category: "Navigation", defaultBinding: ShortcutBinding(keyIdentifier: "h",          command: true,  shift: true,  option: false, control: false)),

        // Editing
        ShortcutActionInfo(name: "moveUp",               displayName: "Move Bullet Up",          category: "Editing",    defaultBinding: ShortcutBinding(keyIdentifier: "upArrow",    command: true,  shift: false, option: false, control: true)),
        ShortcutActionInfo(name: "moveDown",             displayName: "Move Bullet Down",        category: "Editing",    defaultBinding: ShortcutBinding(keyIdentifier: "downArrow",  command: true,  shift: false, option: false, control: true)),
        ShortcutActionInfo(name: "indent",               displayName: "Indent",                  category: "Editing",    defaultBinding: ShortcutBinding(keyIdentifier: "tab",        command: false, shift: false, option: false, control: false)),
        ShortcutActionInfo(name: "outdent",              displayName: "Outdent",                 category: "Editing",    defaultBinding: ShortcutBinding(keyIdentifier: "tab",        command: false, shift: true,  option: false, control: false)),
        ShortcutActionInfo(name: "createSiblingBelow",   displayName: "New Bullet Below",        category: "Editing",    defaultBinding: ShortcutBinding(keyIdentifier: "return",     command: true,  shift: false, option: false, control: false)),
        ShortcutActionInfo(name: "deleteWithChildren",   displayName: "Delete With Children",    category: "Editing",    defaultBinding: ShortcutBinding(keyIdentifier: "delete",     command: true,  shift: true,  option: false, control: false)),
        ShortcutActionInfo(name: "toggleTask",           displayName: "Toggle Task Checkbox",    category: "Editing",    defaultBinding: ShortcutBinding(keyIdentifier: "l",          command: true,  shift: true,  option: false, control: false)),

        // View
        ShortcutActionInfo(name: "toggleFocusMode",      displayName: "Toggle Focus Mode",       category: "View",       defaultBinding: ShortcutBinding(keyIdentifier: "f",          command: true,  shift: true,  option: false, control: false)),
        ShortcutActionInfo(name: "toggleSearch",         displayName: "Toggle Search",           category: "View",       defaultBinding: ShortcutBinding(keyIdentifier: "f",          command: true,  shift: false, option: false, control: false)),
    ]

    /// Default bindings dictionary (action name → binding).
    static let defaults: [String: ShortcutBinding] = {
        var dict: [String: ShortcutBinding] = [:]
        for info in actionDefinitions {
            dict[info.name] = info.defaultBinding
        }
        return dict
    }()

    // MARK: - Binding Lookup

    /// Get the current binding for an action (custom override or default).
    func binding(for actionName: String) -> ShortcutBinding? {
        customBindings[actionName] ?? Self.defaults[actionName]
    }

    /// Reverse lookup: given a key event, find the matching customizable action name.
    /// Returns nil if no customizable action matches (falls through to hardcoded handlers).
    func action(for keyIdentifier: String, command: Bool, shift: Bool, option: Bool, control: Bool) -> String? {
        let lookupKey = Self.reverseLookupKey(keyIdentifier: keyIdentifier, command: command, shift: shift, option: option, control: control)
        return reverseLookup[lookupKey]
    }

    /// Convert an action name to its OutlineAction enum case.
    static func outlineAction(for actionName: String) -> OutlineAction? {
        switch actionName {
        case "collapse":             return .collapse
        case "expand":               return .expand
        case "collapseAll":          return .collapseAll
        case "expandAll":            return .expandAll
        case "moveUp":               return .moveUp
        case "moveDown":             return .moveDown
        case "indent":               return .indent
        case "outdent":              return .outdent
        case "zoomIn":               return .zoomIn
        case "zoomOut":              return .zoomOut
        case "zoomToRoot":           return .zoomToRoot
        case "goHomeAndCollapseAll": return .goHomeAndCollapseAll
        case "toggleTask":           return .toggleTask
        case "toggleFocusMode":      return .toggleFocusMode
        case "toggleSearch":         return .toggleSearch
        case "createSiblingBelow":   return .createSiblingBelow
        case "deleteWithChildren":   return .deleteWithChildren
        default: return nil
        }
    }

    // MARK: - Custom Binding Management

    /// Set a custom binding for an action. Pass nil to reset to default.
    func setCustomBinding(_ binding: ShortcutBinding?, for actionName: String) {
        if let binding = binding, binding != Self.defaults[actionName] {
            customBindings[actionName] = binding
        } else {
            customBindings.removeValue(forKey: actionName)
        }
        saveToSettings()
        rebuildReverseLookup()
    }

    /// Check if an action has a custom (non-default) binding.
    func hasCustomBinding(for actionName: String) -> Bool {
        customBindings[actionName] != nil
    }

    /// Reset a single action to its default binding.
    func resetToDefault(actionName: String) {
        customBindings.removeValue(forKey: actionName)
        saveToSettings()
        rebuildReverseLookup()
    }

    /// Reset all actions to their default bindings.
    func resetAllToDefaults() {
        customBindings.removeAll()
        saveToSettings()
        rebuildReverseLookup()
    }

    /// Check if a binding conflicts with another action (returns conflicting action name, or nil).
    func conflictingAction(for binding: ShortcutBinding, excludingAction: String) -> String? {
        let key = Self.reverseLookupKey(
            keyIdentifier: binding.keyIdentifier,
            command: binding.command,
            shift: binding.shift,
            option: binding.option,
            control: binding.control
        )
        if let existing = reverseLookup[key], existing != excludingAction {
            return existing
        }
        return nil
    }

    // MARK: - Reverse Lookup

    /// Build the reverse lookup table from current bindings.
    private func rebuildReverseLookup() {
        reverseLookup.removeAll()
        for info in Self.actionDefinitions {
            let binding = customBindings[info.name] ?? info.defaultBinding
            let key = Self.reverseLookupKey(
                keyIdentifier: binding.keyIdentifier,
                command: binding.command,
                shift: binding.shift,
                option: binding.option,
                control: binding.control
            )
            reverseLookup[key] = info.name
        }
    }

    /// Create a unique lookup key string from key + modifiers.
    private static func reverseLookupKey(keyIdentifier: String, command: Bool, shift: Bool, option: Bool, control: Bool) -> String {
        "\(keyIdentifier)|\(command ? "1" : "0")\(shift ? "1" : "0")\(option ? "1" : "0")\(control ? "1" : "0")"
    }

    // MARK: - Persistence (via SettingsManager)

    /// Load custom bindings from SettingsManager.
    func loadFromSettings() {
        let data = SettingsManager.shared.customKeyboardShortcutsData
        guard !data.isEmpty else {
            customBindings = [:]
            return
        }
        do {
            customBindings = try JSONDecoder().decode([String: ShortcutBinding].self, from: data)
        } catch {
            print("[Shortcuts] Failed to decode custom bindings: \(error)")
            customBindings = [:]
        }
        rebuildReverseLookup()
    }

    /// Save custom bindings to SettingsManager.
    private func saveToSettings() {
        if customBindings.isEmpty {
            SettingsManager.shared.customKeyboardShortcutsData = Data()
            return
        }
        do {
            let data = try JSONEncoder().encode(customBindings)
            SettingsManager.shared.customKeyboardShortcutsData = data
        } catch {
            print("[Shortcuts] Failed to encode custom bindings: \(error)")
        }
    }

    // MARK: - Key Identifier Converters

    #if os(macOS)
    /// Convert macOS NSEvent keyCode to cross-platform key identifier.
    static func keyIdentifier(from keyCode: UInt16) -> String {
        switch keyCode {
        case 126: return "upArrow"
        case 125: return "downArrow"
        case 123: return "leftArrow"
        case 124: return "rightArrow"
        case 48:  return "tab"
        case 36:  return "return"
        case 51:  return "delete"
        case 53:  return "escape"
        case 49:  return "space"
        case 47:  return "period"
        case 43:  return "comma"
        case 33:  return "openBracket"
        case 30:  return "closeBracket"
        case 44:  return "slash"
        case 42:  return "backslash"
        case 27:  return "minus"
        case 24:  return "equal"
        case 41:  return "semicolon"
        case 39:  return "quote"
        case 50:  return "grave"
        // Letters
        case 0:  return "a"
        case 11: return "b"
        case 8:  return "c"
        case 2:  return "d"
        case 14: return "e"
        case 3:  return "f"
        case 5:  return "g"
        case 4:  return "h"
        case 34: return "i"
        case 38: return "j"
        case 40: return "k"
        case 37: return "l"
        case 46: return "m"
        case 45: return "n"
        case 31: return "o"
        case 35: return "p"
        case 12: return "q"
        case 15: return "r"
        case 1:  return "s"
        case 17: return "t"
        case 32: return "u"
        case 9:  return "v"
        case 13: return "w"
        case 7:  return "x"
        case 16: return "y"
        case 6:  return "z"
        // Numbers
        case 29: return "0"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        // F-keys
        case 122: return "f1"
        case 120: return "f2"
        case 99:  return "f3"
        case 118: return "f4"
        case 96:  return "f5"
        case 97:  return "f6"
        case 98:  return "f7"
        case 100: return "f8"
        case 101: return "f9"
        case 109: return "f10"
        case 103: return "f11"
        case 111: return "f12"
        default:
            return "unknown_\(keyCode)"
        }
    }
    #endif

    #if os(iOS)
    /// Convert iOS UIKeyboardHIDUsage to cross-platform key identifier.
    static func keyIdentifier(from keyCode: UIKeyboardHIDUsage) -> String {
        switch keyCode {
        case .keyboardUpArrow:    return "upArrow"
        case .keyboardDownArrow:  return "downArrow"
        case .keyboardLeftArrow:  return "leftArrow"
        case .keyboardRightArrow: return "rightArrow"
        case .keyboardTab:              return "tab"
        case .keyboardReturnOrEnter:    return "return"
        case .keyboardDeleteOrBackspace: return "delete"
        case .keyboardEscape:           return "escape"
        case .keyboardSpacebar:         return "space"
        case .keyboardPeriod:           return "period"
        case .keyboardComma:            return "comma"
        case .keyboardOpenBracket:      return "openBracket"
        case .keyboardCloseBracket:     return "closeBracket"
        case .keyboardSlash:            return "slash"
        case .keyboardBackslash:        return "backslash"
        case .keyboardHyphen:           return "minus"
        case .keyboardEqualSign:        return "equal"
        case .keyboardSemicolon:        return "semicolon"
        case .keyboardQuote:            return "quote"
        case .keyboardGraveAccentAndTilde: return "grave"
        // Letters
        case .keyboardA: return "a"
        case .keyboardB: return "b"
        case .keyboardC: return "c"
        case .keyboardD: return "d"
        case .keyboardE: return "e"
        case .keyboardF: return "f"
        case .keyboardG: return "g"
        case .keyboardH: return "h"
        case .keyboardI: return "i"
        case .keyboardJ: return "j"
        case .keyboardK: return "k"
        case .keyboardL: return "l"
        case .keyboardM: return "m"
        case .keyboardN: return "n"
        case .keyboardO: return "o"
        case .keyboardP: return "p"
        case .keyboardQ: return "q"
        case .keyboardR: return "r"
        case .keyboardS: return "s"
        case .keyboardT: return "t"
        case .keyboardU: return "u"
        case .keyboardV: return "v"
        case .keyboardW: return "w"
        case .keyboardX: return "x"
        case .keyboardY: return "y"
        case .keyboardZ: return "z"
        // Numbers
        case .keyboard0: return "0"
        case .keyboard1: return "1"
        case .keyboard2: return "2"
        case .keyboard3: return "3"
        case .keyboard4: return "4"
        case .keyboard5: return "5"
        case .keyboard6: return "6"
        case .keyboard7: return "7"
        case .keyboard8: return "8"
        case .keyboard9: return "9"
        // F-keys
        case .keyboardF1:  return "f1"
        case .keyboardF2:  return "f2"
        case .keyboardF3:  return "f3"
        case .keyboardF4:  return "f4"
        case .keyboardF5:  return "f5"
        case .keyboardF6:  return "f6"
        case .keyboardF7:  return "f7"
        case .keyboardF8:  return "f8"
        case .keyboardF9:  return "f9"
        case .keyboardF10: return "f10"
        case .keyboardF11: return "f11"
        case .keyboardF12: return "f12"
        default:
            return "unknown_\(keyCode.rawValue)"
        }
    }
    #endif
}

// MARK: - Key Recorder View (macOS)

#if os(macOS)
/// A view that captures keyboard shortcuts when focused.
/// Click to start recording, press a key combination to set the shortcut.
struct ShortcutRecorderView: NSViewRepresentable {
    let actionName: String
    @Binding var currentBinding: ShortcutBinding
    var onBindingChanged: (ShortcutBinding) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.binding = currentBinding
        view.onCapture = { newBinding in
            onBindingChanged(newBinding)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.binding = currentBinding
        nsView.updateDisplay()
    }
}

/// Custom NSView that captures key events for shortcut recording.
class ShortcutRecorderNSView: NSView {
    var binding: ShortcutBinding?
    var onCapture: ((ShortcutBinding) -> Void)?

    private var isRecording = false
    private let label = NSTextField(labelWithString: "")
    private let recordingLabel = NSTextField(labelWithString: "Press shortcut...")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        recordingLabel.font = .systemFont(ofSize: 11)
        recordingLabel.textColor = .secondaryLabelColor
        recordingLabel.alignment = .center
        recordingLabel.isHidden = true
        recordingLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recordingLabel)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            recordingLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            recordingLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            heightAnchor.constraint(equalToConstant: 24),
        ])

        updateDisplay()
    }

    func updateDisplay() {
        if isRecording {
            label.isHidden = true
            recordingLabel.isHidden = false
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 2
        } else {
            label.isHidden = false
            recordingLabel.isHidden = true
            label.stringValue = binding?.displayString ?? "None"
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 1
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            isRecording = false
            updateDisplay()
        } else {
            isRecording = true
            window?.makeFirstResponder(self)
            updateDisplay()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        let hasShift = flags.contains(.shift)
        let hasOption = flags.contains(.option)
        let hasControl = flags.contains(.control)

        // Escape cancels recording
        if event.keyCode == 53 && !hasCommand && !hasShift && !hasOption && !hasControl {
            isRecording = false
            updateDisplay()
            return
        }

        let keyId = ShortcutManager.keyIdentifier(from: event.keyCode)

        // Require at least one modifier for most keys (except special keys)
        let specialKeys: Set<String> = ["tab", "return", "delete", "escape"]
        if !hasCommand && !hasShift && !hasOption && !hasControl && !specialKeys.contains(keyId) {
            return
        }

        let newBinding = ShortcutBinding(
            keyIdentifier: keyId,
            command: hasCommand,
            shift: hasShift,
            option: hasOption,
            control: hasControl
        )

        isRecording = false
        binding = newBinding
        updateDisplay()
        onCapture?(newBinding)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        if parts.isEmpty {
            recordingLabel.stringValue = "Press shortcut..."
        } else {
            recordingLabel.stringValue = parts.joined() + "..."
        }
    }
}
#endif

// MARK: - Key Recorder View (iOS)

#if os(iOS)
/// A view that captures keyboard shortcuts when focused (requires external keyboard on iOS).
struct ShortcutRecorderView: UIViewRepresentable {
    let actionName: String
    @Binding var currentBinding: ShortcutBinding
    var onBindingChanged: (ShortcutBinding) -> Void

    func makeUIView(context: Context) -> ShortcutRecorderUIView {
        let view = ShortcutRecorderUIView()
        view.binding = currentBinding
        view.onCapture = { newBinding in
            onBindingChanged(newBinding)
        }
        return view
    }

    func updateUIView(_ uiView: ShortcutRecorderUIView, context: Context) {
        uiView.binding = currentBinding
        uiView.updateDisplay()
    }
}

/// Custom UIView that captures key presses for shortcut recording (iOS with external keyboard).
class ShortcutRecorderUIView: UIView {
    var binding: ShortcutBinding?
    var onCapture: ((ShortcutBinding) -> Void)?

    private var isRecording = false
    private let displayLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        backgroundColor = UIColor.secondarySystemBackground

        displayLabel.font = .systemFont(ofSize: 14, weight: .medium)
        displayLabel.textAlignment = .center
        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(displayLabel)

        NSLayoutConstraint.activate([
            displayLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            displayLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            displayLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            displayLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            heightAnchor.constraint(equalToConstant: 32),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        updateDisplay()
    }

    func updateDisplay() {
        if isRecording {
            displayLabel.text = "Press shortcut..."
            displayLabel.textColor = .secondaryLabel
            layer.borderColor = UIColor.tintColor.cgColor
            layer.borderWidth = 2
        } else {
            displayLabel.text = binding?.displayString ?? "None"
            displayLabel.textColor = .label
            layer.borderColor = UIColor.separator.cgColor
            layer.borderWidth = 1
        }
    }

    override var canBecomeFirstResponder: Bool { true }

    @objc private func handleTap() {
        if isRecording {
            isRecording = false
            resignFirstResponder()
            updateDisplay()
        } else {
            isRecording = true
            becomeFirstResponder()
            updateDisplay()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isRecording else {
            super.pressesBegan(presses, with: event)
            return
        }

        for press in presses {
            guard let key = press.key else { continue }

            let hasCommand = key.modifierFlags.contains(.command)
            let hasShift = key.modifierFlags.contains(.shift)
            let hasOption = key.modifierFlags.contains(.alternate)
            let hasControl = key.modifierFlags.contains(.control)

            // Escape cancels recording
            if key.keyCode == .keyboardEscape && !hasCommand && !hasShift && !hasOption && !hasControl {
                isRecording = false
                resignFirstResponder()
                updateDisplay()
                return
            }

            let keyId = ShortcutManager.keyIdentifier(from: key.keyCode)

            // Require at least one modifier for most keys
            let specialKeys: Set<String> = ["tab", "return", "delete", "escape"]
            if !hasCommand && !hasShift && !hasOption && !hasControl && !specialKeys.contains(keyId) {
                return
            }

            let newBinding = ShortcutBinding(
                keyIdentifier: keyId,
                command: hasCommand,
                shift: hasShift,
                option: hasOption,
                control: hasControl
            )

            isRecording = false
            binding = newBinding
            resignFirstResponder()
            updateDisplay()
            onCapture?(newBinding)
            return
        }

        super.pressesBegan(presses, with: event)
    }
}
#endif
