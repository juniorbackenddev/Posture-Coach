//
//  PostureSession.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//
import Foundation
import SwiftData

@Model
final class PostureSession {
    var date: Date
    var duration: TimeInterval        // saniye
    var badPosturePercentage: Double  // 0–100
    var dominantErrorType: String

    init(
        date: Date = .now,
        duration: TimeInterval,
        badPosturePercentage: Double,
        dominantErrorType: String
    ) {
        self.date = date
        self.duration = duration
        self.badPosturePercentage = badPosturePercentage
        self.dominantErrorType = dominantErrorType
    }
}
