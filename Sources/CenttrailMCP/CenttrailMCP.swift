import Foundation
import Ledger

@main
struct CenttrailMCP {
    static func main() {
        do {
            guard let file = try ledgerURL(arguments: Array(CommandLine.arguments.dropFirst())) else { return }
            let ledger = try Ledger.openReadOnly(at: file)
            var session = Session(ledger: ledger)
            while let line = readLine() {
                let response = session.receive(line)
                if let response {
                    let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data([0x0a]))
                }
            }
        } catch {
            FileHandle.standardError.write(Data("centtrail-mcp: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func ledgerURL(arguments: [String]) throws -> URL? {
        if arguments == ["--help"] || arguments == ["-h"] {
            FileHandle.standardError.write(Data("Usage: centtrail-mcp [--ledger PATH]\nOpens the sandboxed Mac app's synced ledger read-only.\n".utf8))
            return nil
        }
        if arguments.isEmpty {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.tejaskale.centtrail/Data/Library/Application Support/Centtrail/ledger-v2.sqlite")
        }
        guard arguments.count == 2, arguments[0] == "--ledger", !arguments[1].isEmpty else {
            throw CommandError.usage
        }
        return URL(fileURLWithPath: (arguments[1] as NSString).expandingTildeInPath)
    }
}

private struct Session {
    let ledger: Ledger
    private var initialized = false
    private var negotiated = false

    init(ledger: Ledger) { self.ledger = ledger }

    mutating func receive(_ line: String) -> [String: Any]? {
        let request: [String: Any]
        do {
            guard line.utf8.count <= 131_072,
                  let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return failure(id: NSNull(), code: -32600, message: "Expected one JSON-RPC object, at most 128 KiB.")
            }
            request = object
        } catch {
            return failure(id: NSNull(), code: -32700, message: "Invalid JSON.")
        }
        let id = request["id"] ?? NSNull()
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return failure(id: id, code: -32600, message: "Expected JSON-RPC 2.0 and a method.")
        }
        // Notifications never receive responses.
        if request["id"] == nil {
            if method == "notifications/initialized", negotiated { initialized = true }
            return nil
        }
        if let params = request["params"], !(params is [String: Any]) {
            return failure(id: id, code: -32602, message: "params must be an object.")
        }
        let params = request["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            guard !negotiated, params["protocolVersion"] is String,
                  params["clientInfo"] is [String: Any], params["capabilities"] is [String: Any] else {
                return failure(id: id, code: -32602, message: "Initialize requires protocolVersion, clientInfo and capabilities, once per session.")
            }
            negotiated = true
            let requested = params["protocolVersion"] as? String ?? ""
            let supported = ["2024-11-05", "2025-03-26", "2025-06-18"]
            return success(id: id, result: [
                "protocolVersion": supported.contains(requested) ? requested : "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "centtrail-mcp", "version": "1.0.0"],
                "instructions": "Use describe_schema first. Amounts have account currencies; never combine currencies. Queries are read-only and capped."
            ])
        case "ping": return success(id: id, result: [:])
        default:
            guard initialized else { return failure(id: id, code: -32000, message: "Initialize the session before calling tools.") }
        }
        switch method {
        case "tools/list": return success(id: id, result: ["tools": Self.tools])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return failure(id: id, code: -32602, message: "Supply a tool name.")
            }
            if let arguments = params["arguments"], !(arguments is [String: Any]) {
                return failure(id: id, code: -32602, message: "Tool arguments must be an object.")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                switch name {
                case "describe_schema":
                    guard arguments.isEmpty else { return failure(id: id, code: -32602, message: "describe_schema takes no arguments.") }
                    return success(id: id, result: text(try ledger.describeSchema()))
                case "query":
                    guard let sql = arguments["sql"] as? String,
                          Set(arguments.keys).isSubset(of: ["sql", "limit"]) else {
                        return failure(id: id, code: -32602, message: "query requires sql and accepts an optional integer limit.")
                    }
                    var limit = 100
                    if let value = arguments["limit"] {
                        guard let number = value as? NSNumber,
                              CFGetTypeID(number) != CFBooleanGetTypeID(),
                              number.doubleValue.isFinite,
                              let integer = Int(exactly: number.doubleValue) else {
                            return failure(id: id, code: -32602, message: "limit must be an integer from 1 to 500.")
                        }
                        limit = integer
                    }
                    let data = try JSONEncoder().encode(ledger.query(sql: sql, limit: limit))
                    return success(id: id, result: text(String(decoding: data, as: UTF8.self)))
                default: return failure(id: id, code: -32602, message: "Unknown tool: \(name)")
                }
            } catch {
                return success(id: id, result: text(error.localizedDescription, isError: true))
            }
        default: return failure(id: id, code: -32601, message: "Unknown method: \(method)")
        }
    }

    private func text(_ value: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": value]], "isError": isError]
    }

    private func success(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func failure(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private static var tools: [[String: Any]] { [
        ["name": "describe_schema", "description": "Explain live tables/views, columns, currencies, amount units and spending rules.",
         "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
         "annotations": ["readOnlyHint": true]],
        ["name": "query", "description": "Run one read-only SQLite query. Default 100 rows; maximum 500 rows, 1 MiB and 2 seconds. Read schema first.",
         "inputSchema": ["type": "object", "properties": [
            "sql": ["type": "string", "description": "One read-only SQL statement."],
            "limit": ["type": "integer", "minimum": 1, "maximum": 500, "default": 100]
         ], "required": ["sql"], "additionalProperties": false],
         "annotations": ["readOnlyHint": true]]
    ] }
}

private enum CommandError: Error, LocalizedError {
    case usage
    var errorDescription: String? { "Usage: centtrail-mcp [--ledger PATH]" }
}
