//
//  CGSPrivate.swift
//  Docky
//
//  SkyLight (CoreGraphics Services) SPI. Compiled out of the App
//  Store / sandboxed build (gated by `APP_STORE_SANDBOX`) so the
//  binary contains zero references to private symbols, `dlopen` of
//  `/System/Library/PrivateFrameworks/SkyLight.framework`, or any
//  of the @_silgen_name bindings below. Apple's static analyzer
//  rejects submissions that ship these symbols at all (not just
//  ones that call them at runtime). The MAS build instead routes
//  every privileged operation through `HelperBridge` (XPC to the
//  side-loaded Developer ID helper).
//

#if !APP_STORE_SANDBOX

import AppKit
import ApplicationServices
import CoreGraphics

typealias CGSConnectionID = Int

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

// Returns the system CGWindowID backing an AX window element. Preferred over
// the AXWindowNumber attribute, which some apps populate with their own
// internal IDs rather than the system window number.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

@_silgen_name("CGSSetWindowBackgroundBlurRadius")
func CGSSetWindowBackgroundBlurRadius(
    _ connection: CGSConnectionID,
    _ windowID: Int,
    _ radius: Int
) -> Int32

@_silgen_name("CGWindowListCreateImage")
func CGWindowListCreateImagePrivate(
    _ screenBounds: CGRect,
    _ listOption: CGWindowListOption,
    _ windowID: CGWindowID,
    _ imageOption: CGWindowImageOption
) -> CGImage?

@_silgen_name("CGSGetWindowAlpha")
func CGSGetWindowAlpha(
    _ connection: CGSConnectionID,
    _ windowID: Int,
    _ alpha: UnsafeMutablePointer<Float>
) -> Int32

@_silgen_name("CGSSetWindowAlpha")
func CGSSetWindowAlpha(
    _ connection: CGSConnectionID,
    _ windowID: Int,
    _ alpha: Float
) -> Int32

// MARK: - SkyLight Process Switching (SLPS)
//
// Used to bring a single window to the front without pulling all of an app's
// other windows above other apps. The standard public path
// (`NSRunningApplication.activate()`) reorders the entire app forward; SLPS
// targets a specific CGWindowID. Same recipe AltTab and DockDoor use.
//
// Loaded via dlopen because the leading-underscore symbol isn't exposed in
// the linker's export table even when CoreGraphics is linked.

struct ProcessSerialNumber {
    var highLongOfPSN: UInt32 = 0
    var lowLongOfPSN: UInt32 = 0
}

@_silgen_name("GetProcessForPID")
func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

enum SLPSMode: UInt32 {
    case allWindows = 0x100
    case userGenerated = 0x200
    case noWindows = 0x400
}

private typealias SLPSSetFrontProcessWithOptionsType = @convention(c) (
    UnsafeMutableRawPointer,
    CGWindowID,
    UInt32
) -> CGError

private typealias SLPSPostEventRecordToType = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeMutablePointer<UInt8>
) -> CGError

private var skyLightHandle: UnsafeMutableRawPointer?
private var setFrontProcessPtr: SLPSSetFrontProcessWithOptionsType?
private var postEventRecordPtr: SLPSPostEventRecordToType?

// Single-threaded-by-convention: focus paths run on main, so the lazy load
// doesn't need a lock.
private func loadSkyLightFunctions() {
    guard skyLightHandle == nil else { return }

    let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    guard let handle = dlopen(skyLightPath, RTLD_LAZY) else { return }
    skyLightHandle = handle

    if let symbol = dlsym(handle, "_SLPSSetFrontProcessWithOptions") {
        setFrontProcessPtr = unsafeBitCast(symbol, to: SLPSSetFrontProcessWithOptionsType.self)
    }
    if let symbol = dlsym(handle, "SLPSPostEventRecordTo") {
        postEventRecordPtr = unsafeBitCast(symbol, to: SLPSPostEventRecordToType.self)
    }
}

@discardableResult
func _SLPSSetFrontProcessWithOptions(
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>,
    _ wid: CGWindowID,
    _ mode: SLPSMode.RawValue
) -> CGError {
    loadSkyLightFunctions()
    guard let fn = setFrontProcessPtr else { return CGError(rawValue: -1)! }
    return fn(psn, wid, mode)
}

@discardableResult
func SLPSPostEventRecordTo(
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>,
    _ bytes: UnsafeMutablePointer<UInt8>
) -> CGError {
    loadSkyLightFunctions()
    guard let fn = postEventRecordPtr else { return CGError(rawValue: -1)! }
    return fn(psn, bytes)
}

/// Posts the two synthetic events SkyLight expects after `SLPSSetFrontProcess`
/// so the targeted window also receives keyboard focus. Without this, the
/// window comes up visually but typing still routes to the previous app —
/// the AltTab/DockDoor "key window" handshake. Byte layout matches DockDoor's
/// implementation exactly; magic offsets are undocumented but known-stable.
func slpsMakeKeyWindow(psn: inout ProcessSerialNumber, windowID: CGWindowID) {
    var bytes = [UInt8](repeating: 0, count: 0xF8)
    bytes[0x04] = 0xF8
    bytes[0x3A] = 0x10
    var wid = UInt32(windowID)
    memcpy(&bytes[0x3C], &wid, MemoryLayout<UInt32>.size)
    memset(&bytes[0x20], 0xFF, 0x10)
    bytes[0x08] = 0x01
    _ = SLPSPostEventRecordTo(&psn, &bytes)
    bytes[0x08] = 0x02
    _ = SLPSPostEventRecordTo(&psn, &bytes)
}

#endif
