//
//  MemoryUsageView.swift
//  SimpleMacStats
//
//  Created by Brandon Dalton on 2/11/24.
//

import SwiftUI

struct MemoryUsageView: View {
    var memoryUsed: Double
    var memoryTotal: Double

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                // Used Memory
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: abs((geometry.size.width * Double(memoryUsed / memoryTotal))))
                
                // Free Memory
                Rectangle()
                    .fill(Color(.darkGray))
                    .frame(width: abs((geometry.size.width * Double((memoryTotal - memoryUsed) / memoryTotal))))
            }
            .frame(height: 20)
        }
    }
}

#Preview {
    MemoryUsageView(memoryUsed: 16.8, memoryTotal: 96.0)
}
