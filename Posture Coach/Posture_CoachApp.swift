//
//  Posture_CoachApp.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//

import SwiftUI
  import SwiftData
                                                                                                                      
  @main
  struct Posture_CoachApp: App {
      var body: some Scene {
          WindowGroup {
              MainView()
                  .modelContainer(for: PostureSession.self)
          }
      }
  }
      
