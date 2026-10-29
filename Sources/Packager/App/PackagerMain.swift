import Foundation
import Darwin

@main
enum PackagerMain {
    private static var termination: DispatchSourceSignal?
    static func main() {
        if CommandLine.arguments.contains("--rpc") {
            // Foundation may put spawned tools in their own process groups.
            // Handle worker termination explicitly so those tools do not outlive it.
            signal(SIGTERM, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
            source.setEventHandler { Shell.cancelAll(); exit(143) }
            source.resume()
            termination = source
            PackageRPC.run()
            return
        }
        if CLIRunner.runIfRequested() { return }
        print("Packager \(AppVersion.current) — use --inspect <package> or open Packager.app")
    }
}
