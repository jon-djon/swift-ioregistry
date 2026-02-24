import Foundation

// Using a class because there is a recursive relationship with parent that struct's don't support
public class IORegistryEntry: Identifiable, CustomStringConvertible {
    public static let separator = "/"

    public let id = UUID()
    public let name: String
    public let plane: String
    public let className: String
    public let bundleName: String
    public let retainCount: UInt32
    public let registryID: UInt64
    public let properties: [IORegistryProperty]
    public var children: [IORegistryEntry]?
    public let parent: IORegistryEntry?

    public static var rootEntry: io_registry_entry_t? {
        let entry = IORegistryGetRootEntry(kIOMainPortDefault)
        guard entry != MACH_PORT_NULL else { return nil }
        return entry
    }

    public static var planes: [String] {
        guard
            let root = IORegistryEntry.rootEntry
        else { return [] }

        let properties = IORegistryEntry.getProperties(root)

        guard
            let registry = properties.first(where: { $0.name == "IORegistryPlanes" }),
            let children = registry.children
        else { return [] }

        return children.map { $0.name }
    }

    public var description: String {
        return name
    }

    public var superClasses: [String] {
        return IORegistryEntry.getSuperClasses(forClass: className)
    }

    public var childEntryCount: Int {
        guard let children else { return 0 }
        return children.reduce(children.count) { $0 + $1.childEntryCount }
    }

    public var sortedChildren: [IORegistryEntry]? {
        if let children = self.children {
            return children.sorted { $0.name < $1.name }
        }
        return nil
    }

    public var parents: [IORegistryEntry] {
        var parents: [IORegistryEntry] = []
        var curParent: IORegistryEntry? = parent
        while let current = curParent {
            parents.append(current)
            curParent = current.parent
        }
        // First 2 items get skipped (Root & Other)
        if parents.count > 2 {
            return Array(parents.reversed()[2...])
        }
        return []
    }

    public var fullPath: String {
        let segments = parents.map { $0.name } + [name]
        return plane + ":/" + segments.joined(separator: IORegistryEntry.separator)
    }

    public static func getProperties(_ entry: io_registry_entry_t) -> [IORegistryProperty] {
        var properties: Unmanaged<CFMutableDictionary>? = nil
        var props: [IORegistryProperty] = []
        guard
            IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
            let _properties = properties?.takeRetainedValue()
        else { return [] }

        guard
            let propsDict = _properties as? [String: Any]
        else { return [] }

        props = propsDict.map { (name, value) in
            IORegistryProperty(name: name, value: value)
        }

        return props.sorted { $0.name < $1.name }
    }

    static func getChildren(
        _ entry: io_registry_entry_t, plane: String, parent: IORegistryEntry? = nil
    ) -> [IORegistryEntry]? {
        var iterator: io_iterator_t = 0
        var children: [IORegistryEntry] = []
        if IORegistryEntryGetChildIterator(entry, plane, &iterator) == KERN_SUCCESS {
            var next = IOIteratorNext(iterator)
            while next != MACH_PORT_NULL {
                if let child = IORegistryEntry(plane: plane, entry: next, parent: parent) {
                    children.append(child)
                }

                IOObjectRelease(next)
                next = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        return children.isEmpty ? nil : children
    }

    public static func getEntryClassName(forEntry entry: io_registry_entry_t) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: Int(MemoryLayout<io_name_t>.size))
        guard IOObjectGetClass(entry, &nameBuffer) == KERN_SUCCESS else { return nil }
        return String(
            decoding: nameBuffer.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
    }

    public static func getEntryName(forEntry entry: io_registry_entry_t) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: Int(MemoryLayout<io_name_t>.size))
        guard IORegistryEntryGetName(entry, &nameBuffer) == KERN_SUCCESS else { return nil }
        return String(
            decoding: nameBuffer.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
    }

    public static func getBundleName(forClass className: String) -> String? {
        // .takeRetainedValue() hands the memory management over to swift ARC
        guard
            let bundle = IOObjectCopyBundleIdentifierForClass(className as CFString)
        else { return nil }
        return bundle.takeRetainedValue() as String
    }

    public static func getSuperClasses(forClass className: String) -> [String] {
        var names: [String] = [className]
        var currentClass = className

        while currentClass != "Unknown",
            let name = IOObjectCopySuperclassForClass(currentClass as CFString?)
        {
            let superclassName = name.takeRetainedValue() as String
            names.append(superclassName)
            currentClass = superclassName
        }
        return names
    }

    public static func getEntryPath(
        for entry: io_registry_entry_t, inPlane plane: String = "IOService"
    ) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: MemoryLayout<io_string_t>.size)
        guard IORegistryEntryGetPath(entry, plane, &pathBuffer) == KERN_SUCCESS else { return nil }
        return String(
            decoding: pathBuffer.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
    }

    public static func getRegistryEntry(forPath path: String) -> IORegistryEntry? {
        let item = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard item != MACH_PORT_NULL else {
            return nil
        }
        defer { IOObjectRelease(item) }

        // Extract the plane from the path prefix (e.g., "IOService:/..." -> "IOService")
        let plane = path.firstIndex(of: ":").map { String(path[..<$0]) } ?? "IOService"

        let entry = IORegistryEntry(plane: plane, entry: item)

        return entry
    }

    public static func getRegistryEntryID(forEntry entry: io_registry_entry_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }

    public init?(plane: String, entry: io_registry_entry_t, parent: IORegistryEntry? = nil) {
        self.plane = plane
        self.parent = parent
        guard
            let name = IORegistryEntry.getEntryName(forEntry: entry),
            let className = IORegistryEntry.getEntryClassName(forEntry: entry),
            let bundleName = IORegistryEntry.getBundleName(forClass: className)
        else { return nil }
        self.name = name
        self.className = className
        self.bundleName = bundleName

        self.retainCount = IOObjectGetRetainCount(entry)

        // Find all properties
        self.properties = IORegistryEntry.getProperties(entry)

        self.registryID = IORegistryEntry.getRegistryEntryID(forEntry: entry)

        // Find all children nodes
        self.children = IORegistryEntry.getChildren(entry, plane: plane, parent: self)
    }
}

extension IORegistryEntry: Hashable {
    public static func == (lhs: IORegistryEntry, rhs: IORegistryEntry) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
