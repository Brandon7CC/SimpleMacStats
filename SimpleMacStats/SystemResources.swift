//
//  SystemResources.swift
//  SimpleMacStats
//
//  Created by Brandon Dalton on 2/9/24.
//

import Foundation
import OSLog
import Observation // To expand the macro

/// Backend handling the fetching of Mac system state:
/// - CPU load (ticks per core -- we're getting this from `mach/processor_info.h`)
/// - Memory usage (we're grabbing this from `mach/vm_statistics.h`)
/// - Connected volume information (this comes from Foundation's `NSFileManager.h`)
@Observable class SystemMonitor {
    
    /// A structure representing the CPU load information.
    /// `mach/processor_info.h`
    struct CpuLoadInfo {
        /// The percentage of time spent executing in user space.
        var user: Float
        /// The percentage of time spent executing in system (kernel) space.
        var system: Float
        /// The percentage of time spent idle.
        var idle: Float
        /// The percentage of time spent executing in low-priority (nice) mode.
        var nice: Float
    }
    
    /// Memory usage information.
    /// `mach/vm_statistics.h`
    struct MemorySnapshot {
        /// The amount of memory actively used (recently used)
        var active: UInt64
        /// Amount of memory wired for the system
        var wired: UInt64
    }
    
    /// Volume usage information
    struct VolumeInfo: Identifiable {
        var id: UUID = UUID()
        
        var path: String
        var capacityGB: Double
        var percentUsed: Double
        var usedSpaceGB: Double {
            capacityGB * (percentUsed / 100.0)
        }
        var freeSpaceGB: Double {
            capacityGB - usedSpaceGB
        }
    }
    
    /// How often do we want to update our view?
    private let UPDATE_INTERVAL: Double = 0.7
    private var timer: Timer?
    private var memSnap: MemorySnapshot?
    
    /// What we're exposing to be published to our view
    /// Intel / Apple Silicon -- to do this we'll use `utsname.h`
    var isAppleSilicon: Bool = true
    var socUsage: Double = 0.0 // Exposed to be published (CPU load)
    var coreCount: Int = 0 // Exposed to be published (core count)
    /// Memory information
    var memoryUsed: Double = 0.0 // Exposed to be published (memory usage)
    var memoryTotal: Double = 0.0 // Exposed to be published (total memory avalible)
    /// Volume information
    var connectedVolumeStats: [VolumeInfo] = [] // Exposed to be published (connected volumes)
    
    /// Initilize the monitor --
    /// - Check the architecture
    /// - Check the connected volumes (this'll be static -- once per app launch)
    /// - Start dynamic async monitoring of CPU load and memory state
    init() {
        isAppleSilicon = isArchAppleSilicon()
        self.connectedVolumeStats = getConnectedVolumeInfo()
        startMonitoring()
    }
    
    /// `utsname.h`
    func isArchAppleSilicon() -> Bool {
        var sysInfo = utsname() // init the struct
        /// Get the Unix name
        if uname(&sysInfo) == 0 {
            /// Get the hardware type "machine"
            let bytes = Data(bytes: &sysInfo.machine, count: Int(_SYS_NAMELEN))
            return String(data: bytes, encoding: .utf8)!.contains("arm64")
        }
        
        return false
    }
    
    /// Handles the async GCD style dynamic stat updates
    func startMonitoring() {
        // Timer for periodic updating based on our defined `UPDATE_INTERVAL`
        timer = Timer.scheduledTimer(withTimeInterval: UPDATE_INTERVAL, repeats: true) { [weak self] _ in
            /// We don't want UI freezes -- async
            DispatchQueue.global().async { [weak self] in
                guard let self = self else { return }
                
                /// Get a snapshot of memory usage
                let memSnapAsync: MemorySnapshot? = getMemoryUsage()
                /// Calculate the CPU load
                let socLoadAsync = calculateCPULoad()
                
                /// ✈️ back to main -- update UI
                DispatchQueue.main.async {
                    self.socUsage = socLoadAsync
                    self.memSnap = memSnapAsync
                }
            }
        }
    }
    
    /// Calculates CPU load between two small points in time
    /// Grabs two snapshots and calculates the load based on the delta between user, system, and idle
    func calculateCPULoad() -> Double {
        // Say cheese
        let firstSnapshot = takeCPUSnapshot()
        sleep(1)
        let secondSnapshot = takeCPUSnapshot()
        
        /// Calculate CPU load
        let deltaUser = secondSnapshot.user - firstSnapshot.user
        let deltaSystem = secondSnapshot.system - firstSnapshot.system
        let deltaIdle = secondSnapshot.idle - firstSnapshot.idle
        let cpuLoad = ((deltaUser + deltaSystem) / (deltaUser + deltaSystem + deltaIdle)) * 100.0
        return Double(cpuLoad)
    }
    
    /// Grab a snapshot of CPU activity across all cores.
    /// To do this we're leveraging state from `host_processor_info` from `processor_info.h`
    /// We'll return the load information: the sum of ticks for each state
    /// - System
    /// - User
    /// - Nice
    /// - Idle
    func takeCPUSnapshot() -> CpuLoadInfo {
        var snapshot = CpuLoadInfo(user: 0.0, system: 0.0, idle: 0.0, nice: 0.0)
        let host = mach_host_self() // Grab the host control port
        var processorInfo: processor_info_array_t?
        var processorMsgCount: mach_msg_type_number_t = 0 // Size of the processorInfo array
        var processorCount: UInt32 = 0
        
        /// We want the flavor `PROCESSOR_CPU_LOAD_INFO` which will get us CPU load information per `mach/processor_info.h`. It'll return:
        /// - processorCount
        /// - processorInfo
        /// - processorMsgCount
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processorCount, &processorInfo, &processorMsgCount)
        guard result == KERN_SUCCESS else {
            os_log("Error calling out to host_processor_info: \(result)")
            return snapshot
        }
        guard let infoArray = processorInfo else {
            os_log("Error calling out to host_processor_info:")
            return snapshot
        }
        
        /// Calculate the number of logical CPUs
        /// `CPU_STATE_MAX` is the number of states the CPU can be in: user, idle, system, and nice (scheduling thing) = 4
        /// processorMsgCount is all the stats for each core -- M1 Pro/Max = CPU_STATE_MAX * 10 = 40
        self.coreCount = Int(processorMsgCount) / Int(CPU_STATE_MAX)
        /// For each core let's get the data we need for each for the 4 states
        for core in 0..<self.coreCount {
            /// Calculate the offset we're at in the array -- this will hold each core's stats so we need to advance
            let offset = core * Int(CPU_STATE_MAX)
            
            /// Grab the ticks for each state for this core (e.g. for core 0 grab `CPU_STATE_USER`)
            let userTicks = Float(infoArray[offset + Int(CPU_STATE_USER)])
            let systemTicks = Float(infoArray[offset + Int(CPU_STATE_SYSTEM)])
            let idleTicks = Float(infoArray[offset + Int(CPU_STATE_IDLE)])
            let niceTicks = Float(infoArray[offset + Int(CPU_STATE_NICE)])
            // print("Core [\(core)] ==> SYSTEM: \(systemTicks), USER: \(userTicks), IDLE: \(idleTicks), NICE: \(niceTicks)")
            
            snapshot.user += userTicks
            snapshot.system += systemTicks
            snapshot.idle += idleTicks
            snapshot.nice += niceTicks
        }
        
        /// Avoid a memory leak by deallocating memory resulted from `host_processor_info`
        let intSize = MemoryLayout<integer_t>.stride
        let totalSizeOfMemoryBlock = intSize * Int(processorMsgCount)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), vm_size_t(totalSizeOfMemoryBlock))
        
        return snapshot
    }
    
    /// Grab memory usage information (64bit only)!
    /// - Total memory avalible to the system (we're using Foundation's `NSProcessInfo`)
    /// - Host virtual memory information with `mach/vm_statistics.h`
    /// References: https://forums.developer.apple.com/forums/thread/712940
    func getMemoryUsage() -> MemorySnapshot {
        var snapshot = MemorySnapshot(active: 0, wired: 0)
        var hostVMInfo = vm_statistics64_data_t() // `mach/vm_statistics.h`
        var vmStatsSize = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        // Closure memory safety reference to a `vm_statistics64_data_t`
        let result = withUnsafeMutablePointer(to: &hostVMInfo) {
            /// Treat our pointer as an `integer_t`
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmStatsSize)) {
                /// Grab the VM info for 64bit systems for our host
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmStatsSize)
            }
        }

        if result == KERN_SUCCESS {
            /// So the memory used will be the page size (`UInt64`) times the number of active pages
            snapshot.active = UInt64(hostVMInfo.active_count) * UInt64(vm_kernel_page_size)
            snapshot.wired = UInt64(hostVMInfo.wire_count) * UInt64(vm_kernel_page_size)
        }
        
        /// Foundation (NSProcessInfo)
        self.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        self.memoryTotal = self.memoryTotal / pow(1024, 3)
        self.memoryUsed = Double(snapshot.wired + snapshot.active) / pow(1024, 3)

        return snapshot
    }
    
    /// Get the usage information across all connected volumes (excluding system)
    /// Leveraging `NSFileManager.h`
    /// To do this we'll first enumerate volumes using `volumeNameKey` next we'll search `mountedVolumeURLs` using the key.
    /// Lastly, we'll calculate usage information with the `volumeTotalCapacityKey` and `volumeAvailableCapacityKey` keys
    func getConnectedVolumeInfo() -> [VolumeInfo] {
        var volumeStats: [VolumeInfo] = []
        let keys: [URLResourceKey] = [.volumeNameKey]
        let volumes: [URL] = FileManager().mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []
        
        let nonSystemURLs: [URL] = volumes.filter({
            !"\($0)".contains("/System")
        })
        
        for volume in nonSystemURLs {
            let volumePath: String = volume.pathComponents.joined(separator: "/").replacingOccurrences(of: "//", with: "/")
            let volumeInfo = try! volume.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            let totalCapacity: Int = volumeInfo.volumeTotalCapacity ?? 0
            let totalAvalible: Int = volumeInfo.volumeAvailableCapacity ?? 0
            let totalCapacityGB: Double = Double(totalCapacity) / pow(1024, 3)
            let totalAvalibleGB: Double = Double(totalAvalible) / pow(1024, 3)
            let percentageUsed: Double = (totalCapacityGB - totalAvalibleGB) / totalCapacityGB * 100
            
            volumeStats.append(VolumeInfo(path: volumePath, capacityGB: totalCapacityGB, percentUsed: percentageUsed))
        }
        
        return volumeStats
    }
}


