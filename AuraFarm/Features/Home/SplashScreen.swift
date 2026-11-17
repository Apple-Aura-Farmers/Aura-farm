//
//  SplashScreen.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 17/11/26.
//

import SwiftUI

struct SplashScreen: View {
    var body: some View {
        Image("Splash_Screen")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
    }
}

/// Shows the splash first, then fades to `content` after a short pause.
struct SplashGate<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var showSplash = true

    var body: some View {
        ZStack {
            content
            if showSplash {
                SplashScreen().transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
        }
    }
}

#Preview {
    SplashScreen()
}
