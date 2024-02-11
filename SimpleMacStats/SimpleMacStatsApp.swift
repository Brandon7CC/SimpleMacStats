//
//  SimpleMacStatsApp.swift
//  SimpleMacStats
//
//  Created by Brandon Dalton on 2/11/24.
//

import SwiftUI


@main
struct SimpleMacStatsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().navigationTitle("System usage").frame(minWidth: 600, maxWidth: 600, minHeight: 600, maxHeight: 600)
        }.windowResizability(.contentSize)
    }
}
