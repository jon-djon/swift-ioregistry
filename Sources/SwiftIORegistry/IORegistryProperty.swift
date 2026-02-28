import Foundation

public enum PropertyValue {
    case string(String)
    case int(Int)
    case uint(UInt64)
    case float(Double)
    case data(Data)
    case array([IORegistryProperty])
    case dictionary([IORegistryProperty])
    case unknown(Any)
}

extension PropertyValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return "0x" + String(v, radix: 16, uppercase: true)
        case .uint(let v): return "0x" + String(v, radix: 16, uppercase: true)
        case .float(let v): return "\(v)"
        case .data(let v):
            return
                "(\(v.count) bytes) \(v.map { String(format: "%02X", $0) }.joined(separator: " "))"
        case .array(let items): return "\(items.count) items"
        case .dictionary(let items): return "\(items.count) items"
        case .unknown: return rawTypeString
        }
    }

    public var typeString: String {
        switch self {
        case .string: return "String"
        case .int: return "Number"
        case .uint: return "Number"
        case .float: return "Number"
        case .data: return "Data"
        case .array: return "Array"
        case .dictionary: return "Dictionary"
        case .unknown: return "Unknown"
        }
    }

    public var rawTypeString: String {
        switch self {
        case .string(let v): return "\(type(of: v))"
        case .int(let v): return "\(type(of: v))"
        case .uint(let v): return "\(type(of: v))"
        case .float(let v): return "\(type(of: v))"
        case .data(let v): return "\(type(of: v))"
        case .array: return "Array"
        case .dictionary: return "Dictionary"
        case .unknown(let v): return "\(type(of: v))"
        }
    }
}

public struct IORegistryProperty: Identifiable, CustomStringConvertible {
    public static let separator = "::"

    public let id = UUID()
    public let name: String
    public let value: PropertyValue

    public init(name: String, value: Any) {
        self.name = name
        if let v = value as? String {
            self.value = .string(v)
        } else if let v = value as? Int {
            self.value = .int(v)
        } else if let v = value as? UInt64 {
            self.value = .uint(v)
        } else if let v = value as? Double {
            self.value = .float(v)
        } else if let v = value as? Data {
            self.value = .data(v)
        } else if let array = value as? NSArray {
            self.value = .array(
                array.enumerated().map { index, element in
                    IORegistryProperty(name: index.description, value: element)
                })
        } else if let dict = value as? [String: Any] {
            self.value = .dictionary(
                dict.map { key, element in
                    IORegistryProperty(name: key, value: element)
                })
        } else {
            self.value = .unknown(value)
        }
    }

    public var children: [IORegistryProperty]? {
        switch value {
        case .array(let items): return items
        case .dictionary(let items): return items
        default: return nil
        }
    }

    public var description: String {
        return name + IORegistryProperty.separator + value.description
    }
}
