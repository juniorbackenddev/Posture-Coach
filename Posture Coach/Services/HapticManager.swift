//
//  HapticManager.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//

import Foundation

#if canImport(UIkit)
import UIKit

final class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    private let warning = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    
    func postureWarning() {warning.notificationOccurred(.warning) }
    func sessionTap() { impact.impactOccurred() }
}

#else
final class HapticManager {
    static let shared = HapticManager()
    private init() {}
    func postureWarning(){}
    func sessionTap(){}
}
#endif
