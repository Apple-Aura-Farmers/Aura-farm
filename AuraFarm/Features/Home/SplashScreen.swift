//
//  SplashScreen.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 17/11/26.
//

import SwiftUI

struct SplashScreen: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Image(scheme == .dark ? "Splash_Screen" : "Splash_Screen_Light")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            Image("Icon")
                .resizable()
                .scaledToFit()
                .frame(width: 132)
        }
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
