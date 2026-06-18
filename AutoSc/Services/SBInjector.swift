import Foundation
import Darwin

final class SBInjector {
    static let shared = SBInjector()
    private(set) var connected = false
    private(set) var lastError = ""

    private init() {}

    func inject() -> Bool {
        if connected { return true }

        /* Find SpringBoard PID */
        let sbPid = findSpringBoardPID()
        guard sbPid > 0 else {
            lastError = "SpringBoard PID not found"
            return false
        }

        /* Get task port */
        var task: task_t = 0
        let kr = task_for_pid(mach_task_self_, sbPid, &task)
        guard kr == KERN_SUCCESS else {
            lastError = "task_for_pid failed: \(kr)"
            return false
        }

        /* Allocate memory in SpringBoard for a small trampoline */
        let pageSize = 0x4000
        var addr: mach_vm_address_t = 0
        let alloc_ret = mach_vm_allocate(task, &addr, mach_vm_size_t(pageSize), VM_FLAGS_ANYWHERE)
        guard alloc_ret == KERN_SUCCESS else {
            lastError = "mach_vm_allocate failed: \(alloc_ret)"
            return false
        }

        /* The trampoline needs to:
           1. Load the HID event system client
           2. Create and dispatch a touch event
           But this is complex - for now, just write a simple test that
           calls dlopen to load a helper dylib from a known path */

        /* Write the path to our dylib into SpringBoard's memory */
        let dylibPath = "/var/tmp/AutoScRemote.dylib"
        let pathData = dylibPath.data(using: .utf8)!
        let pathAddr = addr + 128

        var dest = addr + 128
        let write_ret = mach_vm_write(task, dest, pathData.withUnsafeBytes { $0.baseAddress! }, mach_msg_type_number_t(pathData.count + 1))
        guard write_ret == KERN_SUCCESS else {
            lastError = "mach_vm_write failed: \(write_ret)"
            mach_vm_deallocate(task, addr, mach_vm_size_t(pageSize))
            return false
        }

        lastError = "task_for_pid succeeded but full injection requires more work"
        mach_vm_deallocate(task, addr, mach_vm_size_t(pageSize))
        return false
    }

    private func findSpringBoardPID() -> pid_t {
        let name = "SpringBoard"
        let maxPids = 2000
        var pids = [pid_t](repeating: 0, count: maxPids)
        var bytes = Int32(MemoryLayout<pid_t>.size * maxPids)

        let ret = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * maxPids))
        guard ret > 0 else { return -1 }

        let count = Int(ret)
        for i in 0..<count {
            let pid = pids[i]
            if pid <= 0 { continue }
            var info = proc_bsdshortinfo()
            let ret2 = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdshortinfo>.size))
            if ret2 > 0 {
                let buf = withUnsafePointer(to: info.pbsi_comm) { ptr in
                    ptr.withMemoryRebound(to: UInt8.self, count: Int(MAXCOMLEN)) { p in
                        String(cString: p)
                    }
                }
                if buf == name {
                    return pid
                }
            }
        }
        return -1
    }
}
