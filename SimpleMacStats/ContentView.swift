//
//  ContentView.swift
//  SimpleMacStats
//
//  Created by Brandon Dalton on 2/9/24.
//

import SwiftUI
import Charts

struct ContentView: View {
    @State var monitor = SystemMonitor()
    
    var memoryUsedPercentage: Double {
        if monitor.memoryTotal > 0 {
            return monitor.memoryUsed / monitor.memoryTotal * 100
        }
        return 0.0
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("**Mac Stats Overview**")
                .font(.title).padding(.bottom)
            
            if monitor.isAppleSilicon {
                Text("**SoC load**")
                    .font(.title2)
                    .underline()
            } else {
                Text("**CPU load**")
                    .font(.title2)
                    .underline()
            }
            
            Text("**`\(String(format: "%0.2f", monitor.socUsage))%`** across `\(monitor.coreCount)` cores")
                .font(.title3)
            
            Divider()
            
            Text("**Memory**")
                .font(.title2)
                .underline()
            Text("**Total:** `\(String(format: "%0.2f", monitor.memoryTotal))GB`")
                .font(.title3)
            Text("**In-use:** `\(String(format: "%0.2f", monitor.memoryUsed))GB` (`\(String(format: "%0.2f", memoryUsedPercentage))%`)")
                .font(.title3)
                
            Divider()
            MemoryUsageView(memoryUsed: monitor.memoryUsed, memoryTotal: monitor.memoryTotal)
            
            Divider()
            VolumeChartView(monitor: monitor, connectedVolumeStats: monitor.connectedVolumeStats)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

#Preview {
    ContentView()
}
