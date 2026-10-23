import Foundation
import IOKit.hidsystem
import ServiceManagement

struct KeyRemapping: Equatable {
    let source: UInt64
    let destination: UInt64
    static let f18: UInt64 = 0x70000006d

    // macOS requires Input Monitoring for rewriting these source keys, even
    // when their existing entries are copied unchanged. Never request it.
    var needsInputMonitoring: Bool {
        guard source >> 32 == 7 else { return false }
        let usage = source & 0xffffffff
        return (0x04...0x27).contains(usage) || (0x59...0x64).contains(usage)
            || (0x2d...0x38).contains(usage) || (0x54...0x57).contains(usage) || usage == 0x67
    }

    static func updating(_ entries: [Self], from old: SwitchKey?, to new: SwitchKey?) throws -> [Self] {
        var result = entries
        if let old, old != new {
            // A later change by another tool belongs to that tool.
            result.removeAll { $0 == KeyRemapping(source: old.usage, destination: f18) }
        }
        if let new {
            let mapping = KeyRemapping(source: new.usage, destination: f18)
            guard !result.contains(where: { $0.source == new.usage && $0 != mapping }) else {
                throw SwitchKeyError("다른 설정이 \(new.displayName)을 이미 바꾸고 있어요. 해당 설정을 먼저 해제해 주세요.")
            }
            if !result.contains(mapping) { result.append(mapping) }
        }
        if result != entries && entries.contains(where: \.needsInputMonitoring) {
            throw SwitchKeyError("다른 글자 키 매핑이 있어 권한 없이 함께 갱신할 수 없어요. 해당 매핑을 먼저 해제해 주세요. 입력 모니터링 권한은 요청하지 않아요.")
        }
        return result
    }

}

struct SwitchKeyError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

protocol KeyboardMappingDevice: AnyObject {
    func read() throws -> [KeyRemapping]
    func write(_ entries: [KeyRemapping]) throws
}

/// Reads/writes mapping properties only. This client cannot monitor key events.
final class HIDKeyboardMappings {
    func devices() throws -> [KeyboardMappingDevice] {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            throw SwitchKeyError("키보드 매핑을 조회하지 못했어요.")
        }
        return services.filter {
            (IOHIDServiceClientCopyProperty($0, "PrimaryUsagePage" as CFString) as? NSNumber)?.intValue == 1
                && (IOHIDServiceClientCopyProperty($0, "PrimaryUsage" as CFString) as? NSNumber)?.intValue == 6
        }.map { HIDMappingDevice(client: client, service: $0) }
    }
}

private final class HIDMappingDevice: KeyboardMappingDevice {
    // Keep the client alive for the whole read/write transaction.
    let client: IOHIDEventSystemClient
    let service: IOHIDServiceClient
    init(client: IOHIDEventSystemClient, service: IOHIDServiceClient) {
        self.client = client; self.service = service
    }
    func read() throws -> [KeyRemapping] {
        guard let value = IOHIDServiceClientCopyProperty(service, "UserKeyMapping" as CFString) else { return [] }
        guard let entries = value as? [[String: NSNumber]], entries.allSatisfy({
            Set($0.keys) == ["HIDKeyboardModifierMappingSrc", "HIDKeyboardModifierMappingDst"]
        }) else { throw SwitchKeyError("기존 키 매핑 형식을 읽지 못해 변경하지 않았어요.") }
        return entries.map {
            KeyRemapping(source: $0["HIDKeyboardModifierMappingSrc"]!.uint64Value,
                         destination: $0["HIDKeyboardModifierMappingDst"]!.uint64Value)
        }
    }
    func write(_ entries: [KeyRemapping]) throws {
        let value = entries.map { ["HIDKeyboardModifierMappingSrc": NSNumber(value: $0.source),
                                  "HIDKeyboardModifierMappingDst": NSNumber(value: $0.destination)] }
        guard IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, value as CFArray),
              try read() == entries else {
            throw SwitchKeyError("키 매핑을 적용하지 못했어요. 입력 모니터링 권한은 요청하지 않아요.")
        }
    }
}

enum LoginLaunchState { case off, enabled, needsApproval }
protocol LoginLaunching: AnyObject {
    var state: LoginLaunchState { get }
    func register() throws
    func unregister() throws
}

final class SunaraeLoginLaunch: LoginLaunching {
    var state: LoginLaunchState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }
    func register() throws {
        do { try SMAppService.mainApp.register() }
        catch {
            if state != .needsApproval { throw error }
        }
    }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

protocol SwitchKeyConfiguring: AnyObject {
    var loginNeedsApproval: Bool { get }
    func change(from old: SwitchKey?, to new: SwitchKey?, ownsLoginItem: Bool) throws -> Bool
    func suspend(_ key: SwitchKey) throws
    func restore(_ key: SwitchKey) throws
}

final class SwitchKeyConfiguration: SwitchKeyConfiguring {
    private let devices: () throws -> [KeyboardMappingDevice]
    private let login: LoginLaunching
    var loginNeedsApproval: Bool { login.state != .enabled }

    init(devices: @escaping () throws -> [KeyboardMappingDevice], login: LoginLaunching) {
        self.devices = devices; self.login = login
    }
    static func live() -> SwitchKeyConfiguration {
        let mappings = HIDKeyboardMappings()
        return SwitchKeyConfiguration(devices: mappings.devices, login: SunaraeLoginLaunch())
    }

    private struct Change {
        let device: KeyboardMappingDevice
        let before: [KeyRemapping]
        let after: [KeyRemapping]
    }
    private func plan(from old: SwitchKey?, to new: SwitchKey?) throws -> [Change] {
        try devices().compactMap { device in
            let before = try device.read()
            let after = try KeyRemapping.updating(before, from: old, to: new)
            return before == after ? nil : Change(device: device, before: before, after: after)
        }
    }
    private func apply(_ changes: [Change]) throws {
        var attempted: [Change] = []
        do {
            for change in changes {
                guard try change.device.read() == change.before else {
                    throw SwitchKeyError("다른 도구가 키 매핑을 바꿨어요. 상태를 확인한 뒤 다시 적용해 주세요.")
                }
                attempted.append(change)
                try change.device.write(change.after)
            }
        } catch {
            var rollbackFailed = false
            for change in attempted.reversed() {
                do {
                    let current = try change.device.read()
                    if current == change.after { try change.device.write(change.before) }
                    else if current != change.before { rollbackFailed = true }
                } catch { rollbackFailed = true }
            }
            if rollbackFailed {
                throw SwitchKeyError("키 매핑 적용과 일부 복원에 실패했어요. 전환 키 설정을 다시 적용해 상태를 확인해 주세요.")
            }
            throw error
        }
    }

    /// Changes mappings and login registration as one recoverable operation.
    func change(from old: SwitchKey?, to new: SwitchKey?, ownsLoginItem: Bool) throws -> Bool {
        let changes = try plan(from: old, to: new)
        if new != nil {
            let addedLogin = login.state == .off
            if addedLogin { try login.register() }
            do { try apply(changes) }
            catch {
                if addedLogin {
                    do { try login.unregister() }
                    catch { throw SwitchKeyError("매핑 적용에 실패했고 로그인 항목도 해제하지 못했어요. 시스템 설정의 로그인 항목을 확인해 주세요.") }
                }
                throw error
            }
            return ownsLoginItem || addedLogin
        }
        let removedLogin = ownsLoginItem && login.state != .off
        if removedLogin { try login.unregister() }
        do { try apply(changes) }
        catch {
            if removedLogin {
                do { try login.register() }
                catch { throw SwitchKeyError("매핑 해제에 실패했고 로그인 항목도 복원하지 못했어요. 시스템 설정의 로그인 항목을 확인해 주세요.") }
            }
            throw error
        }
        return false
    }
    // Recording needs the physical key, not the mapped F18. Keep login settings.
    func suspend(_ key: SwitchKey) throws { try apply(plan(from: key, to: nil)) }
    func restore(_ key: SwitchKey) throws { try apply(plan(from: key, to: key)) }
}
