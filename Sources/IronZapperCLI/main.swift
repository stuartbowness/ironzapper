import Foundation
import IronZapperCore

@main struct ScanCLI {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            print("Usage: ironzapper-scan /Applications/Example.app\nRead-only scan; never removes files.")
            return
        }
        let report = try AppScanner().scan(URL(fileURLWithPath: CommandLine.arguments[1]))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    }
}
