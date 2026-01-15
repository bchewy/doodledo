//
//  ContentView.swift
//  doodledo
//
//  Created by brianchew on 15/1/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = DoodleStore()

    var body: some View {
        HomeView()
            .environmentObject(store)
    }
}

#Preview {
    ContentView()
}
