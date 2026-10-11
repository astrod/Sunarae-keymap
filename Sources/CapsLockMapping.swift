import Foundation
import IOKit.hidsystem
import ServiceManagement

struct KeyRemapping: Equatable {
    let source: UInt64
    let destination: UInt64
    static let capsLock: UInt64 = 0x700000039
    static let f18: UInt64 = 0x70000006d
    static let capsToF18 = KeyRemapping(source: capsLock, destination: f18)

    // macOS requires Input Monitoring for rewriting these source keys, even
    // when their existing entries are copied unchanged. Never request it.
    var needsInputMonitoring: Bool {
        guard source >> 32 == 7 else { return false }
        let usage = source & 0xffffffff
        return (0x04...0x27).contains(usage) || (0x59...0x64).contains(usage)
            || (0x2d...0x38).contains(usage) || (0x54...0x57).contains(usage) || usage == 0x67
    }

    static func updating(_ entries: [Self], enabled: Bool) throws -> [Self] {
        var result = entries
        if enabled {
            guard !entries.contains(where: { $0.source == capsLock && $0 != capsToF18 }) else {
                throw CapsLockError("다른 설정이 Caps Lock을 이미 바꾸고 있어요. 그 설정을 해제한 뒤 다시 적용해 주세요.")
            }
            if !result.contains(capsToF18) { result.append(capsToF18) }
        } else {
            // A later change by another tool belongs to that tool.
            result.removeAll { $0 == capsToF18 }
        }
        if result != entries && entries.contains(where: \.needsInputMonitoring) {
            throw CapsLockError("다른 글자 키 매핑이 있어 권한 없이 함께 갱신할 수 없어요. 해당 매핑을 먼저 해제해 주세요. 입력 모니터링 권한은 요청하지 않아요.")
        }
        return result
    }
}

struct CapsLockError: LocalizedError {
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
            throw CapsLockError("키보드 매핑을 조회하지 못했어요.")
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
        }) else { throw CapsLockError("기존 키 매핑 형식을 읽지 못해 변경하지 않았어요.") }
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
            throw CapsLockError("키 매핑을 적용하지 못했어요. 입력 모니터링 권한은 요청하지 않아요.")
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

protocol CapsLockConfiguring: AnyObject {
    var loginNeedsApproval: Bool { get }
    func enable() throws -> Bool
    func disable(removeLoginItem: Bool) throws
    func restore() throws
}

final class CapsLockConfiguration: CapsLockConfiguring {
    private let devices: () throws -> [KeyboardMappingDevice]
    private let login: LoginLaunching
    var loginNeedsApproval: Bool { login.state != .enabled }

    init(devices: @escaping () throws -> [KeyboardMappingDevice], login: LoginLaunching) {
        self.devices = devices; self.login = login
    }
    static func live() -> CapsLockConfiguration {
        let mappings = HIDKeyboardMappings()
        return CapsLockConfiguration(devices: mappings.devices, login: SunaraeLoginLaunch())
    }

    private struct Change {
        let device: KeyboardMappingDevice
        let before: [KeyRemapping]
        let after: [KeyRemapping]
    }
    private func plan(enabled: Bool) throws -> [Change] {
        try devices().compactMap { device in
            let before = try device.read()
            let after = try KeyRemapping.updating(before, enabled: enabled)
            return before == after ? nil : Change(device: device, before: before, after: after)
        }
    }
    private func apply(_ changes: [Change]) throws {
        var attempted: [Change] = []
        do {
            for change in changes {
                guard try change.device.read() == change.before else {
                    throw CapsLockError("다른 도구가 키 매핑을 바꿨어요. 상태를 확인한 뒤 다시 적용해 주세요.")
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
                throw CapsLockError("키 매핑 적용과 일부 복원에 실패했어요. Caps Lock 설정을 다시 적용해 상태를 확인해 주세요.")
            }
            throw error
        }
    }

    /// Returns whether this feature owns the login registration.
    func enable() throws -> Bool {
        let changes = try plan(enabled: true)
        let ownsLogin = login.state == .off
        if ownsLogin { try login.register() }
        do { try apply(changes) }
        catch {
            if ownsLogin {
                do { try login.unregister() }
                catch { throw CapsLockError("매핑 적용에 실패했고 로그인 항목도 해제하지 못했어요. 시스템 설정의 로그인 항목을 확인해 주세요.") }
            }
            throw error
        }
        return ownsLogin
    }
    func disable(removeLoginItem: Bool) throws {
        let changes = try plan(enabled: false)
        let wasRegistered = login.state != .off
        if removeLoginItem && wasRegistered { try login.unregister() }
        do { try apply(changes) }
        catch {
            if removeLoginItem && wasRegistered {
                do { try login.register() }
                catch { throw CapsLockError("매핑 해제에 실패했고 로그인 항목도 복원하지 못했어요. 시스템 설정의 로그인 항목을 확인해 주세요.") }
            }
            throw error
        }
    }
    func restore() throws { try apply(plan(enabled: true)) }
}
