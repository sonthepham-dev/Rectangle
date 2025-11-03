//
//  TitleBarManager.swift
//  Rectangle
//
//  Copyright © 2023 Ryan Hanson. All rights reserved.
//

import Foundation

class TitleBarManager {
    private var eventMonitor: EventMonitor!
    private var lastEventNumber: Int?

    init() {
        eventMonitor = PassiveEventMonitor(mask: .leftMouseUp, handler: handle)
        toggleListening()
        Notification.Name.windowTitleBar.onPost { notification in
            self.toggleListening()
        }
        Notification.Name.configImported.onPost { notification in
            self.toggleListening()
        }
    }
    
    private func toggleListening() {
        if WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil {
            eventMonitor.start()
        } else {
            eventMonitor.stop()
        }
    }
    
    private func handle(_ event: NSEvent) {
        guard
            event.type == .leftMouseUp,
            event.clickCount == 2,
            event.eventNumber != lastEventNumber,
            TitleBarManager.systemSettingDisabled,
            let action = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1),
            case let location = NSEvent.mouseLocation.screenFlipped,
            let element = AccessibilityElement(location)?.getSelfOrChildElementRecursively(location),
            let windowElement = element.windowElement,
            var titleBarFrame = windowElement.titleBarFrame
        else {
            return
        }
        lastEventNumber = event.eventNumber
        if let toolbarFrame = windowElement.getChildElement(.toolbar)?.frame, toolbarFrame != .null {
            // Only include toolbars that are at the top of the window (near the title bar).
            // Status bars at the bottom of windows (like in VSCode) are also exposed as toolbars
            // but should not be included in the title bar detection area.
            let currentWindowFrame = windowElement.frame
            if currentWindowFrame != .null {
                let windowHeight = currentWindowFrame.height
                // In screenFlipped coordinates, maxY is the top edge
                // Check if toolbar's top edge is near the window's top edge (within upper 30%)
                let distanceFromTop = currentWindowFrame.maxY - toolbarFrame.maxY
                // Consider toolbar as "top toolbar" if it's within the upper 30% of the window
                // This prevents status bars at the bottom from being incorrectly included
                if distanceFromTop >= 0 && distanceFromTop < windowHeight * 0.3 {
                    titleBarFrame = titleBarFrame.union(toolbarFrame)
                }
            }
        }
        guard
            titleBarFrame.contains(location),
            element.isWindow == true || element.isToolbar == true || element.isGroup == true || element.isTabGroup == true || element.isStaticText == true
        else {
            return
        }
        if let ignoredApps = Defaults.doubleClickTitleBarIgnoredApps.typedValue,
            !ignoredApps.isEmpty,
            let pid = element.pid,
            let appId = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
            ignoredApps.contains(appId) {
            return
        }
        if Defaults.doubleClickTitleBarRestore.enabled != false,
           let windowId = windowElement.windowId,
           case let windowFrame = windowElement.frame,
           windowFrame != .null,
           let historyAction = AppDelegate.windowHistory.lastRectangleActions[windowId],
           historyAction.action == action,
           historyAction.rect == windowFrame {
            WindowAction.restore.postTitleBar(windowElement: windowElement)
            return
        }
        action.postTitleBar(windowElement: windowElement)
    }
}

extension TitleBarManager {
    static var systemSettingDisabled: Bool {
        UserDefaults(suiteName: ".GlobalPreferences")?.string(forKey: "AppleActionOnDoubleClick") == "None"
    }
}
