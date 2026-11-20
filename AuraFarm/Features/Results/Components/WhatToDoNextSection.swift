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
/// advice is for and keeps it alive across redraws. It starts the advice when it first appears;
/// the view model keeps the load running, so scrolling away from it cannot cut it off. Try again
/// and Write again start it over.
struct WhatToDoNextSection: View {
    let viewModel: SoilResultViewModel
    /// A line under the advice, for what it was and was not based on.
    var footer: String?

    var body: some View {
        Section {
            RecommendationCard(
                state: viewModel.recommendationState,
                modelUnavailableReason: viewModel.modelUnavailableReason,
                progress: viewModel.progress,
                basis: viewModel.adviceBasis,
                updateNote: viewModel.updateNote,
                savedAt: viewModel.savedAt,
                savedFromOlderRules: viewModel.savedFromOlderRules,
                rating: viewModel.feedback?.rating,
                onRate: { rating, reasons in
                    Task { await viewModel.rate(rating, reasons: reasons) }
                },
                onWriteAgain: viewModel.canWriteAgain ? { viewModel.restart(freshWording: true) } : nil,
                onRetry: { viewModel.restart(freshWording: viewModel.wantsFreshWording) }
            )
            .onAppear { viewModel.startIfNeeded() }
        } header: {
            Text("What to do next")
        } footer: {
            if let footer { Text(footer) }
        }
    }
}
