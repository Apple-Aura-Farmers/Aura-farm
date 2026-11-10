//
//  WhatToDoNextSection.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 10/11/26.
//

import SwiftUI

/// "What to do next": the advice written for one test, with the question of whether it was
/// useful and a way to write it again.
///
/// It takes the view model rather than making one, so whoever shows it decides which test the
/// advice is for and keeps it alive across redraws. It asks for the advice when its card
/// appears, and again on Try again or Write again.
struct WhatToDoNextSection: View {
    let viewModel: SoilResultViewModel
    /// A line under the advice, for what it was and was not based on.
    var footer: String?

    /// Bumped by Try again and Write again, to restart the recommendation task.
    @State private var attempt = 0

    var body: some View {
        Section {
            RecommendationCard(
                state: viewModel.recommendationState,
                modelUnavailableReason: viewModel.modelUnavailableReason,
                progress: viewModel.progress,
                basis: viewModel.adviceBasis,
                savedAt: viewModel.savedAt,
                savedFromOlderRules: viewModel.savedFromOlderRules,
                rating: viewModel.feedback?.rating,
                onRate: { rating, reasons in
                    Task { await viewModel.rate(rating, reasons: reasons) }
                },
                onRetry: { attempt += 1 }
            )
            .task(id: attempt) {
                await viewModel.loadRecommendation(freshWording: viewModel.wantsFreshWording)
            }
            if viewModel.canWriteAgain {
                Button("Write again", systemImage: "arrow.clockwise") {
                    viewModel.requestFreshWording()
                    attempt += 1
                }
            }
        } header: {
            Text("What to do next")
        } footer: {
            if let footer { Text(footer) }
        }
    }
}
