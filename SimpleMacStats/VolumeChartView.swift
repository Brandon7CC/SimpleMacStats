//
//  VolumeInfoView.swift
//  SimpleMacStats
//
//  Created by Brandon Dalton on 2/11/24.
//

import SwiftUI
import Charts

struct VolumeChartView: View {
    @State var monitor: SystemMonitor
    var connectedVolumeStats: [SystemMonitor.VolumeInfo]

    var body: some View {
        Text("**Total volumes: `\(connectedVolumeStats.count)`**")
            .font(.title2)
            .underline()
            .help("Excluding System!")
        
        /// Horizontal view for connected volumes
        ScrollView(.horizontal) {
            HStack {
                ForEach(connectedVolumeStats) { volume in
                    VStack(alignment: .leading) {
                        Text("**Volume path:** `\(volume.path)`")
                            .font(.headline)
                            .padding(.bottom)
                            .frame(alignment: .leading)
                        
                        Chart {
                            /// Used space
                            SectorMark(
                                angle: .value("Used", volume.usedSpaceGB)
                            )
                            .foregroundStyle(Color(.darkGray))

                            /// Free space
                            SectorMark(
                                angle: .value("Free", volume.freeSpaceGB)
                            )
                            .foregroundStyle(.yellow)
                        }
                        .chartForegroundStyleScale([
                            "Used": Color(.darkGray),
                            "Free": .yellow
                        ])
                        .frame(width: 200, height: 200)
                        Text("\(String(format: "%0.2f", 100.0 - volume.percentUsed))% free of \(String(format: "%0.2f", volume.capacityGB))GB")
                    }
                    .padding()
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
