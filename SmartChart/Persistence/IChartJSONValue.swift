import Foundation

enum IChartJSONValue: Codable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([IChartJSONValue])
    case object([String: IChartJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([IChartJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: IChartJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    static func chartPayload(for chart: Chart) throws -> IChartJSONValue {
        let data = try ChartPersistenceCoders.encoder.encode(chart)
        return try JSONDecoder().decode(IChartJSONValue.self, from: data)
    }

    func decodeChart() throws -> Chart {
        let data = try JSONEncoder().encode(self)
        return try ChartPersistenceCoders.decoder.decode(Chart.self, from: data)
    }
}
