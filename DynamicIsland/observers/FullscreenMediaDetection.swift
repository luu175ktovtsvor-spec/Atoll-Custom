/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Defaults
import MacroVisionKit
import SwiftUI

@MainActor
class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    private let detector: FullScreenMonitor
    @ObservedObject private var musicManager = MusicManager.shared
    @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private var notificationTask: Task<Void, Never>?

    private init() {
        self.detector = FullScreenMonitor.shared
        setupNotificationObservers()
        Task { [weak self] in
            await self?.updateFullScreenStatus()
        }
    }

    private func setupNotificationObservers() {
        notificationTask = Task { @Sendable [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let activeSpaceNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.activeSpaceDidChangeNotification
                    )
                    
                    for await _ in activeSpaceNotifications {
                        await self?.handleChange()
                    }
                }
                
                group.addTask {
                    let screenParameterNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named:  NSApplication.didChangeScreenParametersNotification
                    )
                    
                    for await _ in screenParameterNotifications {
                        await  self?.handleChange()
                    }
                }
            }
        }
    }

    private func handleChange() async {
        try? await Task.sleep(for: .milliseconds(500))
        await self.updateFullScreenStatus()
    }

    private func updateFullScreenStatus() async {
        guard Defaults[.enableFullscreenMediaDetection] else {
            let reset = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { ($0.localizedName, false) })
            if reset != fullscreenStatus {
                fullscreenStatus = reset
            }
            return
        }

        let spaces = await detector.detectFullscreenApps(debug: false)
        let names = NSScreen.screens.map { $0.localizedName }
        let hideOption = Defaults[.hideNotchOption]

        var newStatus = Dictionary(uniqueKeysWithValues: names.map { ($0, false) })
        for space in spaces {
            guard let screen = await detector.screen(for: space) else { continue }
            let name = screen.localizedName

            let runningApps = space.runningApps.filter { $0 != "com.apple.finder" }
            switch hideOption {
            case .always:
                newStatus[name] = !runningApps.isEmpty
            case .nowPlayingOnly:
                if let bundleIdentifier = musicManager.bundleIdentifier {
                    newStatus[name] = runningApps.contains(bundleIdentifier)
                } else {
                    newStatus[name] = false
                }
            case .never:
                newStatus[name] = false
            }
        }

        if newStatus != fullscreenStatus {
            fullscreenStatus = newStatus
            NSLog("✅ Fullscreen status: \(newStatus)")
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
