import Foundation
import Carbon
import CoreServices

let bundleID = "local.inputmethod.Sunarae"
func property(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}
func sources(identifier: String = bundleID) -> [TISInputSource] {
    let filter = [kTISPropertyBundleID as String: identifier] as CFDictionary
    guard let result = TISCreateInputSourceList(filter, true) else { return [] }
    return result.takeRetainedValue() as? [TISInputSource] ?? []
}
func currentIdentifier() -> String {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let id = property(source, kTISPropertyInputSourceID), !id.isEmpty else {
        fail("현재 입력기를 확인하지 못했어요")
    }
    return id
}
func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
}
func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
func check(_ status: OSStatus, _ message: String) {
    if status != noErr { fail("\(message) (macOS status \(status))") }
}
// Read the prior identity from a recognized app, without embedding old names.
func identity(at url: URL) -> String {
    guard let info = Bundle(url: url)?.infoDictionary,
          let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
          info["CFBundleExecutable"] as? String == "Sunarae",
          info["InputMethodServerControllerClass"] as? String == "SunaraeInputController",
          info["InputMethodConnectionName"] as? String == id + "_Connection",
          info["TISInputSourceID"] as? String == id else { fail("순아래 입력기 파일이 아니에요") }
    return id
}
func disable(_ identifier: String) {
    if currentIdentifier().hasPrefix(identifier) {
        fail("먼저 입력기를 ABC 또는 다른 한글 입력기로 바꿔 주세요.")
    }
    for source in sources(identifier: identifier) {
        check(TISDisableInputSource(source), "입력 소스에서 제거하지 못했어요")
    }
}
let arguments = CommandLine.arguments
guard arguments.count >= 2 else { fail("Usage: input-source current|select-abc|register PATH|register-only PATH|inspect PATH|enabled PATH|disable-bundle PATH|disable|trash PATH|list|status") }
func appURL() -> URL {
    guard arguments.count == 3 else { fail("An app path is required") }
    return URL(fileURLWithPath: arguments[2])
}
switch arguments[1] {
case "current":
    print(currentIdentifier())
case "select-abc":
    let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.ABC"] as CFDictionary
    guard let result = TISCreateInputSourceList(filter, false),
          let source = (result.takeRetainedValue() as? [TISInputSource])?.first else {
        fail("ABC 입력 소스가 없어요. 다른 입력기로 바꾼 뒤 설치해 주세요.")
    }
    check(TISSelectInputSource(source), "ABC로 전환하지 못했어요")
case "inspect":
    print(identity(at: appURL()))
case "enabled":
    print(sources(identifier: identity(at: appURL())).contains { flag($0, kTISPropertyInputSourceIsEnabled) })
case "register", "register-only":
    let url = appURL(), identifier = identity(at: url)
    check(LSRegisterURL(url as CFURL, true), "앱 실행 경로를 등록하지 못했어요")
    check(TISRegisterInputSource(url as CFURL), "입력기를 등록하지 못했어요")
    let available = sources(identifier: identifier)
    if available.isEmpty {
        print("두벌식 순아래를 등록했지만 macOS 입력기 목록이 아직 갱신되지 않았어요.")
        print("로그아웃 후 다시 로그인하고, 시스템 설정 → 키보드 → 텍스트 입력 → 편집에서 추가해 주세요.")
        break
    }
    if arguments[1] == "register" {
        for source in available { check(TISEnableInputSource(source), "입력기를 활성화하지 못했어요") }
    }
    print("두벌식 순아래를 등록했어요.")
    if sources(identifier: identifier).contains(where: { flag($0, kTISPropertyInputSourceIsEnabled) }) {
        print("입력 메뉴에서 두벌식 순아래를 선택하고, macOS 사용 승인 요청을 직접 확인해 주세요.")
    } else {
        print("시스템 설정 → 키보드 → 텍스트 입력 → 편집에서 두벌식 순아래를 추가해 주세요.")
    }
case "disable":
    disable(bundleID)
case "disable-bundle":
    disable(identity(at: appURL()))
case "trash":
    let url = appURL()
    _ = identity(at: url)
    do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    catch { fail("휴지통으로 이동하지 못했어요: \(error.localizedDescription)") }
case "list":
    for source in sources() { print(property(source, kTISPropertyInputSourceID) ?? "unknown") }
case "status":
    let available = sources()
    if available.isEmpty { print("registered=false") }
    for source in available {
        print("name=\(property(source, kTISPropertyLocalizedName) ?? "unknown") registered=true enabled=\(flag(source, kTISPropertyInputSourceIsEnabled)) selected=\(flag(source, kTISPropertyInputSourceIsSelected))")
    }
default:
    fail("Unknown command")
}
