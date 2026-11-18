import Foundation
import IOBluetooth
import IOKit
import IOKit.hid

/// A wireless accessory whose charge can be read from the system.
struct DeviceBattery: Identifiable, Equatable {
    enum Kind: String {
        case mouse
        case keyboard
        case trackpad
        case headphones
        case gamepad
        case other

        var symbolName: String {
            switch self {
            case .mouse: "computermouse"
            case .keyboard: "keyboard"
            case .trackpad: "rectangle.and.hand.point.up.left"
            case .headphones: "headphones"
            case .gamepad: "gamecontroller"
            case .other: "battery.100percent"
            }
        }
    }

    enum Source {
        /// Apple's HID event service, used by Magic Mouse / Keyboard / Trackpad.
        case appleHID
        /// Logitech's HID++ 2.0 battery feature, used by Logitech mice and keyboards.
        case logitechHIDPP
    }

    let id: String
    let name: String
    let kind: Kind
    let percent: Int?
    let isCharging: Bool?
    let source: Source

    var fraction: Double? {
        percent.map { min(1, max(0, Double($0) / 100)) }
    }

    var percentText: String {
        percent.map { "\($0)%" } ?? "—"
    }

    /// True when the gauge is known and in the warning range. Charging devices never warn.
    var isLowBattery: Bool {
        guard isCharging != true, let fraction else { return false }
        return fraction < 0.20
    }

    /// Short status used in help text and menu items, e.g. "20% · charging".
    var statusText: String {
        isCharging == true ? "\(percentText) · charging" : percentText
    }
}

// MARK: - Sampler

enum DeviceBatterySampler {
    static func read() -> [DeviceBattery] {
        let bluetoothNames = bluetoothNamesByAddress()
        var devices = appleHIDDevices(names: bluetoothNames)
        devices.append(contentsOf: logitechDevices())

        // A device can be visible through more than one path; keep the entry that has a level.
        var byID: [String: DeviceBattery] = [:]
        for device in devices {
            if let existing = byID[device.id], existing.percent != nil, device.percent == nil {
                continue
            }
            byID[device.id] = device
        }

        return byID.values.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return kindRank(lhs.kind) < kindRank(rhs.kind)
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func kindRank(_ kind: DeviceBattery.Kind) -> Int {
        switch kind {
        case .mouse: 0
        case .keyboard: 1
        case .trackpad: 2
        case .headphones: 3
        case .gamepad: 4
        case .other: 5
        }
    }

    // MARK: Apple HID devices

    private static func appleHIDDevices(names: [String: String]) -> [DeviceBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleDeviceManagementHIDEventService"),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [DeviceBattery] = []
        var service = IOIteratorNext(iterator)

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let properties = registryProperties(of: service) else { continue }
            guard (properties["HasBattery"] as? Bool) == true,
                  let percent = integer(properties["BatteryPercent"]) else { continue }

            let address = (properties["DeviceAddress"] as? String)
                ?? (properties["SerialNumber"] as? String)
                ?? ""
            let normalizedAddress = normalizeAddress(address)
            let product = trimmedString(properties["Product"])
            let category = trimmedString(properties["Accessory Category"])

            let name = names[normalizedAddress]
                ?? (product.isEmpty ? fallbackName(for: category) : product)
            let id = "apple:\(normalizedAddress.isEmpty ? name : normalizedAddress)"

            result.append(
                DeviceBattery(
                    id: id,
                    name: name,
                    kind: kind(for: category, name: name),
                    percent: min(100, max(0, percent)),
                    isCharging: nil,
                    source: .appleHID
                )
            )
        }

        return result
    }

    private static func registryProperties(of service: io_object_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private static func bluetoothNamesByAddress() -> [String: String] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return [:]
        }

        var names: [String: String] = [:]
        for device in paired {
            guard let address = device.addressString else { continue }
            let name = (device.nameOrAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            names[normalizeAddress(address)] = name
        }
        return names
    }

    // MARK: Logitech HID++ devices

    private static func logitechDevices() -> [DeviceBattery] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        // Copying the device list works even when opening the manager for input is refused.
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        // Logitech accessories expose several HID interfaces. Keep the one most likely to
        // carry HID++ long reports, keyed by the stable serial number.
        var candidates: [String: (device: IOHIDDevice, score: Int)] = [:]
        for device in devices {
            guard integer(IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString)) == 0x046D else {
                continue
            }

            let product = trimmedString(IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString))
            let serial = trimmedString(IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString))
            let uniqueID = trimmedString(IOHIDDeviceGetProperty(device, "PhysicalDeviceUniqueID" as CFString))
            let key = !serial.isEmpty ? serial : (!uniqueID.isEmpty ? uniqueID : product)
            guard !key.isEmpty else { continue }

            let maxOutput = integer(IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString)) ?? 0
            let usages = deviceUsagePairs(device)
            let hasVendorPage = usages.contains { $0.page == 0xFF43 }
            let score = (hasVendorPage ? 4 : 0) + (maxOutput >= 20 ? 2 : 0)

            if let existing = candidates[key], existing.score >= score {
                continue
            }
            candidates[key] = (device, score)
        }

        var result: [DeviceBattery] = []
        for (key, candidate) in candidates {
            guard let battery = logitechBattery(device: candidate.device) else { continue }

            let product = trimmedString(IOHIDDeviceGetProperty(candidate.device, kIOHIDProductKey as CFString))
            let name = product.isEmpty ? "Logitech Device" : product
            result.append(
                DeviceBattery(
                    id: "logi:\(key)",
                    name: name,
                    kind: kind(for: nil, name: name, device: candidate.device),
                    percent: battery.percent,
                    isCharging: battery.isCharging,
                    source: .logitechHIDPP
                )
            )
        }
        return result
    }

    private static func logitechBattery(device: IOHIDDevice) -> (percent: Int?, isCharging: Bool?)? {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        var softwareID = UInt8.random(in: 1...15)

        func request(feature: UInt8, function: UInt8, params: [UInt8] = []) -> [UInt8]? {
            defer { softwareID = softwareID == 15 ? 1 : softwareID + 1 }
            return hidppRequest(
                device: device,
                feature: feature,
                function: function,
                params: params,
                softwareID: softwareID
            )
        }

        func featureIndex(_ feature: UInt16) -> UInt8? {
            guard let response = request(
                feature: 0x00,
                function: 0x00,
                params: [UInt8(feature >> 8), UInt8(feature & 0xFF)]
            ), response.count > 4 else {
                return nil
            }
            let index = response[4]
            return index == 0 ? nil : index
        }

        // Unified battery (newer devices): capabilities tell us whether byte 0 is a percentage.
        if let index = featureIndex(0x1004),
           let capabilities = request(feature: index, function: 0x00),
           let info = request(feature: index, function: 0x01),
           capabilities.count > 5, info.count > 6 {
            let hasPercentage = capabilities[5] & 0x02 != 0
            let status = Int(info[6])
            let percent: Int?
            if hasPercentage {
                percent = min(100, max(0, Int(info[4])))
            } else {
                percent = percentage(forLevel: info[5])
            }
            let charging: Bool? = switch status {
            case 1, 2, 4: true
            case 3: true
            case 0, 5, 6, 7: false
            default: nil
            }
            return (status == 3 ? 100 : percent, charging)
        }

        // Legacy battery status (MX Master and older devices).
        if let index = featureIndex(0x1000),
           let info = request(feature: index, function: 0x00),
           info.count > 6 {
            let level = Int(info[4])
            let status = Int(info[6])
            let charging: Bool? = switch status {
            case 1, 2, 4: true
            case 3: true
            case 0, 5, 6, 7: false
            default: nil
            }

            if status == 3 {
                return (100, charging)
            }
            if level > 0 {
                return (min(100, level), charging)
            }
            // A zero reading in a charging state means the gauge is unknown, not empty.
            return (nil, charging)
        }

        return nil
    }

    private static func percentage(forLevel level: UInt8) -> Int? {
        switch level {
        case 1: 5
        case 2: 20
        case 3: 40
        case 4: 60
        case 5: 70
        case 6: 80
        case 7: 90
        case 8: 100
        default: nil
        }
    }

    private static func hidppRequest(
        device: IOHIDDevice,
        feature: UInt8,
        function: UInt8,
        params: [UInt8],
        softwareID: UInt8
    ) -> [UInt8]? {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11
        report[1] = 0xFF
        report[2] = feature
        report[3] = (function << 4) | (softwareID & 0x0F)
        for (index, value) in params.enumerated() where 4 + index < report.count {
            report[4 + index] = value
        }

        let writeResult = report.withUnsafeBufferPointer { pointer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                0x11,
                pointer.baseAddress!,
                pointer.count
            )
        }
        guard writeResult == kIOReturnSuccess else { return nil }

        let deadline = Date().addingTimeInterval(0.5)
        var buffer = [UInt8](repeating: 0, count: 64)

        while Date() < deadline {
            var length = buffer.count
            let readResult = IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeInput,
                0x11,
                &buffer,
                &length
            )

            if readResult == kIOReturnSuccess, length > 4, buffer[0] == 0x11 {
                if buffer[2] == 0xFF {
                    return nil
                }
                if buffer[2] == feature, buffer[3] & 0x0F == softwareID & 0x0F {
                    return Array(buffer.prefix(Int(length)))
                }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        return nil
    }

    // MARK: Shared helpers

    private struct UsagePair {
        let page: Int
        let usage: Int
    }

    private static func deviceUsagePairs(_ device: IOHIDDevice) -> [UsagePair] {
        guard let pairs = IOHIDDeviceGetProperty(device, "DeviceUsagePairs" as CFString) as? [[String: Any]] else {
            return []
        }
        return pairs.compactMap { pair in
            guard let page = integer(pair["DeviceUsagePage"]),
                  let usage = integer(pair["DeviceUsage"]) else {
                return nil
            }
            return UsagePair(page: page, usage: usage)
        }
    }

    private static func kind(for category: String?, name: String, device: IOHIDDevice? = nil) -> DeviceBattery.Kind {
        let haystack = "\(category ?? "") \(name)".lowercased()
        if haystack.contains("trackpad") { return .trackpad }
        if haystack.contains("keyboard") { return .keyboard }
        if haystack.contains("mouse") { return .mouse }
        if haystack.contains("headphone") || haystack.contains("airpod") || haystack.contains("earbud") {
            return .headphones
        }
        if haystack.contains("gamepad") || haystack.contains("controller") { return .gamepad }

        if let device {
            let pairs = deviceUsagePairs(device)
            if pairs.contains(where: { $0.page == 1 && $0.usage == 2 }) { return .mouse }
            if pairs.contains(where: { $0.page == 1 && $0.usage == 5 }) { return .gamepad }
            if pairs.contains(where: { $0.page == 1 && $0.usage == 6 }) { return .keyboard }
        }
        return .other
    }

    private static func fallbackName(for category: String) -> String {
        category.isEmpty ? "Wireless Device" : category
    }

    private static func normalizeAddress(_ address: String) -> String {
        address
            .lowercased()
            .filter { $0.isHexDigit }
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: number.intValue
        case let int as Int: int
        case let string as String: Int(string)
        default: nil
        }
    }

    private static func trimmedString(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}