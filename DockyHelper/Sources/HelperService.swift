//
//  HelperService.swift
//  DockyHelper
//
//  Concrete implementation of `DockyHelperProtocol`. Today only
//  `ping(reply:)` is wired up; real methods (focusWindow,
//  applyBlur, mediaSnapshot, hideSystemDock, captureWindow, etc.)
//  arrive one at a time as the MAS bridge's private-API call sites
//  are migrated to call through the helper.
//

import Foundation

final class HelperService: NSObject, DockyHelperProtocol {
    func ping(reply: @escaping (String) -> Void) {
        reply("pong:v1")
    }
}
