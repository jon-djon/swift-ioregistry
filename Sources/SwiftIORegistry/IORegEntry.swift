import Foundation


// Using a class because there is a recursive relationship with parent that struct's don't support
public class IORegEntry: Identifiable, CustomStringConvertible {
    public static let seperator = "/"
    
    public let id = UUID()
    public let name: String
    public let plane: String
    public let className: String
    public let bundleName: String
    public let retainCount: UInt32
    public let registryID: UInt64
    public let properties: [IORegProperty]
    public var children: [IORegEntry]?
    public let parent: IORegEntry?
    
    
    public static var rootEntry: io_registry_entry_t? {
        let entry = IORegistryGetRootEntry( kIOMainPortDefault )
        guard entry != MACH_PORT_NULL else { return nil }
        return entry
    }
    
    public static var planes: [String] {
        guard
            let root = IORegEntry.rootEntry
        else { return [] }
        
        let properties = IORegEntry.getProperties(root)
        
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
        return IORegEntry.getSuperClasses(forClass: className)
    }
    
    public lazy var childEntryCount: Int = {
        var count = 0
        if let children = self.children {
            count = children.count
            children.forEach { count += $0.childEntryCount }
        }
        return count
    }()
    
    public var sortedChildren:[IORegEntry]? {
        if let children = self.children {
            return children.sorted { $0.name < $1.name }
        }
        return nil
    }
    
    public var parents: [IORegEntry] {
        guard let parent = parent else { return [] }
        var parents: [IORegEntry] = []
        var curParent:IORegEntry? = parent
        while curParent != nil {
            if let _parent = curParent {
                parents.append(_parent)
                curParent = _parent.parent
            }
        }
        // First 2 items get skipped (Root & Other)
        if parents.count > 2 {
            return Array(parents.reversed()[2...])
        }
        return []
    }
    
    public var fullPath: String {
        return plane + ":/" + parents.map { $0.name }.joined(separator: IORegEntry.seperator) + IORegEntry.seperator + name
    }
    
    
    public static func getProperties(_ entry: io_registry_entry_t) -> [IORegProperty] {
        var properties: Unmanaged<CFMutableDictionary>? = nil
        var props:[IORegProperty] = []
        guard
            IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let _properties = properties?.takeRetainedValue()
        else { return [] }
        
        // TODO: what should be here, the release causes a crash
        // defer { properties?.release() }
        
        guard
            let propsDict = _properties as? [ String : Any ]
        else { return [] }
        
        props = propsDict.map { (name, value) in
            IORegProperty(name:name , value: value)
        }
        
        return props
    }
    
    public static func getChildren(_ entry: io_registry_entry_t, plane: String, parent: IORegEntry? = nil) -> [IORegEntry]? {
        var iterator: io_iterator_t = 0
        var children:[IORegEntry] = []
        if IORegistryEntryGetChildIterator(entry, plane, &iterator) == KERN_SUCCESS {
            var next = IOIteratorNext(iterator)
            while next != 0 {
                if let child = IORegEntry(plane: plane, entry: next, parent: parent) {
                    children.append(child)
                }
                
                IOObjectRelease(next)
                next = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        return children
    }
    
    public static func getEntryClassName(forEntry entry: io_registry_entry_t) -> String? {
        let name = UnsafeMutablePointer<io_name_t>.allocate(capacity: 1)
        defer { name.deallocate() }
        guard IOObjectGetClass(entry, name) == KERN_SUCCESS else { return nil }
        return String(cString: UnsafeRawPointer(name).assumingMemoryBound(to: CChar.self))
    }
    
    public static func getEntryName(forEntry entry: io_registry_entry_t) -> String? {
        let name = UnsafeMutablePointer<io_name_t>.allocate(capacity: 1)
        defer { name.deallocate() }
        guard IORegistryEntryGetName(entry, name) == KERN_SUCCESS else { return nil }
        return String(cString: UnsafeRawPointer(name).assumingMemoryBound(to: CChar.self))
    }
    
    public static func getBundleName(forClass className: String) -> String? {
        let name = UnsafeMutablePointer<io_name_t>.allocate(capacity: 1)
        defer { name.deallocate() }
        guard
            let bundle = IOObjectCopyBundleIdentifierForClass(className as CFString)?.takeRetainedValue() as String?
        else { return nil }
        return bundle
    }
    
    public static func getSuperClasses(forClass className: String) -> [String] {
        var names:[String] = [className]
        var parent = className
        
        while let name = IOObjectCopySuperclassForClass(parent as CFString?)?.takeRetainedValue() as String? {
            names.append(name)
            parent = name
        }
        return names
    }
    
    public static func getEntryPath(forEntry entry: io_registry_entry_t) -> String? {
        let path = UnsafeMutablePointer<io_name_t>.allocate(capacity: 1)
        defer { path.deallocate() }
        guard IORegistryEntryGetPath(entry, kIOServicePlane, path) == KERN_SUCCESS else { return nil }
        return String(cString: UnsafeRawPointer(path).assumingMemoryBound(to: CChar.self))
    }
    
    public static func getRegistryEntry(forPath path: String) -> io_registry_entry_t? {
        let item = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard item != .zero else {
            return nil
        }
        // defer { IOObjectRelease(item) }
        return item
    }
    
    public static func getIORegEntryFromPath(_ path: String) -> IORegEntry? {
        guard let ioEntry = IORegEntry.getRegistryEntry(forPath: path) else { return nil }
        defer { IOObjectRelease(ioEntry) }
        return IORegEntry(plane: "", entry: ioEntry )
    }
    
    public static func getRegistryEntryID(forEntry entry: io_registry_entry_t) -> UInt64 {
        var id: UInt64 = 0
        let item = IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }
    
    
    public init?(plane: String, entry: io_registry_entry_t, parent: IORegEntry? = nil) {
        self.plane = plane
        self.parent = parent
        guard
            let name = IORegEntry.getEntryName(forEntry: entry),
            let className = IORegEntry.getEntryClassName(forEntry: entry),
            let bundleName = IORegEntry.getBundleName(forClass: className)
        else { return nil }
        self.name = name
        self.className = className
        self.bundleName = bundleName
        
        self.retainCount = IOObjectGetRetainCount(entry)
        
        // Find all properties
        self.properties = IORegEntry.getProperties(entry)
        
        self.registryID = IORegEntry.getRegistryEntryID(forEntry: entry)
        
        // Find all children nodes
        self.children = IORegEntry.getChildren(entry, plane: plane, parent: self)
        if self.children?.count == 0 {
            self.children = nil
        }
    }
}


extension IORegEntry: Hashable {
    public static func == (lhs: IORegEntry, rhs: IORegEntry) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}