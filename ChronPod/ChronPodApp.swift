// ChronPod — an iOS podcast and legal-news player derived from AntennaPod.
// Copyright (C) 2026 Richard S. Patterson and contributors.
//
// This program is free software: you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version. See LICENSE.

import SwiftUI
import ChronPodCore

@main
struct ChronPodApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var downloads = DownloadManager()
    @StateObject private var player = PlayerController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(downloads)
                .environmentObject(player)
                .tint(Theme.accent)
                .task {
                    player.attach(library: library, downloads: downloads)
                    await library.bootstrap()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { library.saveNow() }
        }
    }
}

enum Theme {
    /// ChronLaw maroon.
    static let accent = Color(red: 0.55, green: 0.09, blue: 0.16)
    static let navy = Color(red: 0.06, green: 0.10, blue: 0.19)
    static let gold = Color(red: 0.79, green: 0.64, blue: 0.15)
}
