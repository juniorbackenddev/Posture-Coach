//
//  HistoryView.swift
//  Posture Coach
//
//  Created by Yasin on 4.05.2026.
//

import SwiftUI
  import SwiftData
  import Charts

  struct HistoryView: View {
      @Query(sort: \PostureSession.date, order: .reverse) private var sessions: [PostureSession]
      @Environment(\.modelContext) private var context
  
      var body: some View {
          List {
              if !sessions.isEmpty {
                  Section("Son 7 Seans") {
                      Chart(sessions.prefix(7)) { s in
                          BarMark(
                              x: .value("Tarih", s.date, unit: .day),
                              y: .value("Kötü %", s.badPosturePercentage)
                          )
                          .foregroundStyle(s.badPosturePercentage > 40 ? Color.red : Color.green)
                      }
                      .chartYScale(domain: 0...100)
                      .frame(height: 160)
                  }
              }
                                                                                                                      
              Section("Tüm Seanslar") {
                  if sessions.isEmpty {
                      ContentUnavailableView(
                          "Henüz seans yok",
                          systemImage: "figure.stand",
                          description: Text("İlk seanstan sonra burada görünecek.")
                      )
                  } else {
                      ForEach(sessions) { s in
                          SessionRow(session: s)
                      }
                      .onDelete { offsets in
                          offsets.forEach { context.delete(sessions[$0]) }
                          try? context.save()
                      }
                  }
              }
          }
          .navigationTitle("Geçmiş")
      }
  }

  private struct SessionRow: View {
      let session: PostureSession
                                                                                                                        
      var body: some View {
          VStack(alignment: .leading, spacing: 4) {
              HStack {
                  Text(session.date.formatted(date: .abbreviated, time: .shortened))
                      .font(.subheadline.bold())
                  Spacer()
                  Text(formatDuration(session.duration))
                      .font(.caption.monospacedDigit())
                      .foregroundStyle(.secondary)
              }
              HStack(spacing: 6) {
                  Label(String(format: "%.0f%% kötü", session.badPosturePercentage),
                        systemImage: "figure.slouch")
                      .foregroundStyle(session.badPosturePercentage > 40 ? .red : .secondary)
                  if session.dominantErrorType != "Yok" {
                      Text("·")
                      Text(session.dominantErrorType)
                  }
              }
              .font(.caption)
          }
          .padding(.vertical, 2)
      }

      private func formatDuration(_ t: TimeInterval) -> String {
          String(format: "%dm %02ds", Int(t) / 60, Int(t) % 60)
      }
  }
