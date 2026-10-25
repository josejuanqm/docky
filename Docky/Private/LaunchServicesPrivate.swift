//
//  LaunchServicesPrivate.swift
//  Docky
//
//  LaunchServices SPI, the same calls `lsappinfo` uses. Not for App Store submission without review.
//

import CoreFoundation
import Darwin

// The application serial number LaunchServices keys its per-app information on.
@_silgen_name("_LSASNCreateWithPid")
func _LSASNCreateWithPid(_ allocator: CFAllocator?, _ pid: pid_t) -> Unmanaged<CFTypeRef>?

// The "StatusLabel" item holds the dock badge an app sets, as `["label": String]`.
@_silgen_name("_LSCopyApplicationInformationItem")
func _LSCopyApplicationInformationItem(_ sessionID: Int32, _ asn: CFTypeRef, _ key: CFString) -> Unmanaged<CFTypeRef>?

/// `kLSDefaultSessionID`.
let kLSDefaultSessionID: Int32 = -2
