//
//  HistoryViewModel.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//


import Foundation
import SwiftData

@MainActor
final class HistoryViewModel {
    var sessions: [PostureSession] = []
    
    var averageBadPosture: Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.map(\.badPosturePercentage).reduce(0, +) / Double(sessions.count)
    }
    
    var totalTime: TimeInterval {
        sessions.map(\.duration).reduce(0, +)
    }
    
    func load(context: ModelContext) {
        let descriptor = FetchDescriptor<PostureSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        sessions = (try? context.fetch(descriptor)) ?? []
    }
}
