import Foundation

/// The executable's commands for scripts and agents, answered before the app starts:
///
///     macsbored path            where config.json is
///     macsbored check [file]    each problem with its line; exits 1 if there's an error
///     macsbored schema          the JSON Schema the file follows
public enum ConfigCommand {
    public struct Outcome: Equatable, Sendable {
        public var output: String
        public var status: Int32

        public init(output: String, status: Int32) {
            self.output = output
            self.status = status
        }
    }

    /// The command `arguments` name (without the program's own path), or nil when they're the app's.
    public static func run(_ arguments: [String], defaultURL: URL) -> Outcome? {
        guard let command = arguments.first else { return nil }
        switch command {
        case "path":
            return Outcome(output: defaultURL.path, status: 0)
        case "schema":
            return Outcome(output: ConfigSchema.text, status: 0)
        case "check":
            let url = arguments.count > 1 ? URL(fileURLWithPath: arguments[1]) : defaultURL
            guard let data = try? Data(contentsOf: url) else {
                return Outcome(output: "\(url.path): can't be read.", status: 1)
            }
            let reading = ConfigFile.read(data)
            guard !reading.issues.isEmpty else { return Outcome(output: "\(url.path): no problems.", status: 0) }
            let lines = reading.issues.map { issue in
                "\(url.path)\(issue.line.map { ":\($0)" } ?? ""): \(issue.isWarning ? "warning" : "error"): \(issue.message)"
            }
            return Outcome(output: lines.joined(separator: "\n"), status: reading.errors.isEmpty ? 0 : 1)
        default:
            return nil
        }
    }
}
