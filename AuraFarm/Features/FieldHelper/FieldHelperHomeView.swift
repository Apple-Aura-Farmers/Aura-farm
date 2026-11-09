//
//  FieldHelperHomeView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// PLACEHOLDER: the Field Helper side of the app has not been designed yet. This stands in
/// for its first screen so the role picker has somewhere to go, and keeps the way back to
/// the picker.
struct FieldHelperHomeView: View {
    /// Sends the person back to the role picker.
    var onSwitchRole: () -> Void

    var body: some View {
        NavigationStack {
            VStack {
                Text("Field Helpers")
            }
            ContentUnavailableView(
                "Field Helper",
                systemImage: "leaf.fill",
                description: Text("This part of the app is coming soon.")
            )
            .navigationTitle("Field Helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onSwitchRole) {
                        Label("Switch role", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
        }
    }
}

#Preview {
    FieldHelperHomeView(onSwitchRole: {})
}
