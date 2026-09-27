import Foundation
import LARMCore

let args = CommandLine.arguments
let socketPath = Paths.socketURL.path
let spoolDir = Paths.spoolDir.path

var input: [String: Any] = [:]
if args.contains("--test") {
    input = ["hook_event_name": "LARMTest", "session_id": "larm-test", "tool_name": "LARMTest"]
} else {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    input = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? ["hook_event_name": args.dropFirst().first ?? "unknown"]
    if input["hook_event_name"] == nil, let e = args.dropFirst().first { input["hook_event_name"] = e }
}
let ppid = getppid()
let ev = HookClassifier.classify(input, ppid: ppid, processStart: HookClassifier.processStartTime(pid: ppid))
let how = HookTransport.deliver(ev, socketPath: socketPath, spoolDir: spoolDir)
if args.contains("--test") { print("larm-hook test event delivered via \(how)") }
exit(0)
