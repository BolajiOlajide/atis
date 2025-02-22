//
//  ContentView.swift
//  atis
//
//  Created by Bolaji Olajide on 26/07/2024.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            DirectorySelector()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
