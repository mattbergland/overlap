import SwiftUI
import AppKit
import Carbon

/// Global ⌥⇧O-style hotkey via Carbon RegisterEventHotKey (no deps).
@Observable
final class HotKeyManager {
    static let shared = HotKeyManager()

    @ObservationIgnored @AppStorage("overlap.hotkey.keyCode") var keyCode: Int = Int(kVK_ANSI_O)
    @ObservationIgnored @AppStorage("overlap.hotkey.mods") var modifiers: Int = optionKey | shiftKey
    @ObservationIgnored @AppStorage("overlap.hotkey.enabled") var enabled = true

    /// Fires on the main thread when the hotkey is pressed.
    var handler: (() -> Void)?

    /// Set from the ⋯ menu to show the recorder sheet.
    var showRecorder = false

    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?

    private init() {
        installHandler()
        if enabled { register() }
    }

    /// Display string for the current shortcut ("⌥⇧O" or "off").
    var label: String {
        guard enabled else { return "off" }
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        s += Self.keyName(keyCode)
        return s
    }

    static func keyName(_ code: Int) -> String {
        // Carbon virtual keycodes → glyph
        let names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "␣", kVK_Return: "↩", kVK_Tab: "⇥",
        ]
        return names[code] ?? "#\(code)"
    }

    func set(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.enabled = true
        register()
    }

    func disable() {
        enabled = false
        unregister()
    }

    func register() {
        unregister()
        var hk = EventHotKeyRef?.none
        var id = EventHotKeyID()
        id.signature = OSType(0x4F564C50) // 'OVLP'
        id.id = 1
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                            GetApplicationEventTarget(), 0, &hk)
        hotKeyRef = hk
    }

    private func unregister() {
        if let r = hotKeyRef { UnregisterEventHotKey(r) }
        hotKeyRef = nil
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ref -> OSStatus in
            guard let ref else { return noErr }
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(ref).takeUnretainedValue()
            DispatchQueue.main.async { mgr.handler?() }
            return noErr
        }, 1, &spec, userData, &handlerRef)
    }
}

/// Small NSView that captures the next key-down with ≥1 modifier.
/// Esc cancels; the callback receives Carbon key code + modifier flags.
final class HotKeyCaptureView: NSView {
    var onCapture: ((Int, Int) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        var mods = 0
        let f = event.modifierFlags
        if f.contains(.control) { mods |= controlKey }
        if f.contains(.option) { mods |= optionKey }
        if f.contains(.shift) { mods |= shiftKey }
        if f.contains(.command) { mods |= cmdKey }
        guard mods != 0 else { return }
        onCapture?(Int(event.keyCode), mods)
    }
}

struct HotKeyRecorder: NSViewRepresentable {
    var onCapture: (Int, Int) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> HotKeyCaptureView {
        let v = HotKeyCaptureView()
        v.onCapture = onCapture
        v.onCancel = onCancel
        return v
    }

    func updateNSView(_ nsView: HotKeyCaptureView, context: Context) { }
}
