import Foundation

public struct IORegProperty: Identifiable, CustomStringConvertible {
    public static let seperator = "::"
    
    public let id = UUID()
    public let name: String
    public let value: Any
    
    public var typeString: String
    public var children: [IORegProperty]? = nil
    
    public init(name: String, value: Any) {
        self.name = name
        self.value = value
        self.typeString = "Unknown"
    
        if let _ = value as? String {
            self.typeString = "String"
        } else if let _ = value as? Int {
            self.typeString = "Number"
        } else if let array = value as? NSArray {
            self.typeString = "Array"
            self.children = array.enumerated().map { index,value in
                IORegProperty(name: index.description, value: value)
            }
        } else if let dict = value as? [String:Any] {
            self.typeString = "Dictionary"
            self.children = dict.map { name,value in
                IORegProperty(name: name, value: value)
            }
        }
    }
    
    public var rawTypeString: String {
        return "\(type(of: value))"
    }
    
    public var stringValue: String {
        if typeString == "Array" || typeString == "Dictionary" {
            if let children = self.children {
                return "\(children.count) items"
            }
            return "0 items"
        } else if let ret = value as? String {
            return ret
        } else if let ret = value as? Int {
            return String(ret, radix: 16, uppercase: true)
        }
        return rawTypeString
    }
    
    public var description: String {
        return name + IORegProperty.seperator + stringValue
    }
}
