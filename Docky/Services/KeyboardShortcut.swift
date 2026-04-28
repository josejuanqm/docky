//
//  KeyboardShortcut.swift
//  Docky
//

import AppKit
import Carbon
import Foundation

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlagsRawValue: UInt

    static let empty = KeyboardShortcut(keyCode: 0, modifierFlags: [])

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlags.intersection(Self.supportedModifierFlags).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue).intersection(Self.supportedModifierFlags)
    }

    var isValid: Bool {
        !modifierFlags.isEmpty
    }

    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0

        if modifierFlags.contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if modifierFlags.contains(.option) {
            flags |= UInt32(optionKey)
        }
        if modifierFlags.contains(.control) {
            flags |= UInt32(controlKey)
        }
        if modifierFlags.contains(.shift) {
            flags |= UInt32(shiftKey)
        }

        return flags
    }

    var displayString: String {
        guard isValid else {
            return "Not Set"
        }

        let modifierDisplay = Self.modifierDisplayString(for: modifierFlags)
        let keyDisplay = Self.keyDisplayString(for: keyCode)
        return modifierDisplay + keyDisplay
    }

    var releaseInstruction: String {
        let modifierDisplay = Self.modifierDisplayString(for: modifierFlags)
        return modifierDisplay.isEmpty ? "Release shortcut to switch" : "Release \(modifierDisplay) to switch"
    }

    static let supportedModifierFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    static func from(event: NSEvent) -> KeyboardShortcut? {
        let modifiers = event.modifierFlags.intersection(supportedModifierFlags)
        let shortcut = KeyboardShortcut(keyCode: event.keyCode, modifierFlags: modifiers)
        return shortcut.isValid ? shortcut : nil
    }

    static func modifierDisplayString(for flags: NSEvent.ModifierFlags) -> String {
        var components: [String] = []

        if flags.contains(.control) {
            components.append("⌃")
        }
        if flags.contains(.option) {
            components.append("⌥")
        }
        if flags.contains(.shift) {
            components.append("⇧")
        }
        if flags.contains(.command) {
            components.append("⌘")
        }

        return components.joined()
    }

    static func keyDisplayString(for keyCode: UInt16) -> String {
        if let specialKey = specialKeyNames[keyCode] {
            return specialKey
        }

        if let character = characterKeyNames[keyCode] {
            return character
        }

        return "Key \(keyCode)"
    }

    private static let specialKeyNames: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        123: "Left Arrow",
        124: "Right Arrow",
        125: "Down Arrow",
        126: "Up Arrow",
    ]

    private static let characterKeyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
        17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
        25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U",
        33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
    ]
}
