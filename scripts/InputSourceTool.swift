import Foundation
import Carbon
import CoreServices

let bundleID = "local.inputmethod.Dukkeobi"
func property(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}
func sources() -> [TISInputSource] {
    let filter = [kTISPropertyBundleID as String: bundleID] as CFDictionary
    guard let result = TISCreateInputSourceList(filter, true) else { return [] }
    return result.takeRetainedValue() as? [TISInputSource] ?? []
}
func current() -> TISInputSource { TISCopyCurrentKeyboardInputSource().takeRetainedValue() }
func currentIdentifier() -> String {
    guard let id = property(current(), kTISPropertyInputSourceID), !id.isEmpty else {
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
let arguments = CommandLine.arguments
guard arguments.count >= 2 else { fail("Usage: input-source current|register PATH|register-only PATH|disable|trash PATH|list|status") }
switch arguments[1] {
case "current":
    print(currentIdentifier())
case "register", "register-only":
    guard arguments.count == 3 else { fail("An app path is required") }
    let url = URL(fileURLWithPath: arguments[2])
    guard Bundle(url: url)?.bundleIdentifier == bundleID else { fail("This is not the Sunarae input method") }
    // A rename keeps the input-source ID but changes its executable path.
    // Refresh Launch Services before TIS so macOS launches the new bundle.
    check(LSRegisterURL(url as CFURL, true), "앱 실행 경로를 등록하지 못했어요")
    check(TISRegisterInputSource(url as CFURL), "입력기를 등록하지 못했어요")
    let available = sources()
    if available.isEmpty {
        // Registration succeeded. Keep the installed bundle while macOS
        // refreshes its list; a failure exit would make the installer remove it.
        print("두벌식 순아래를 등록했지만 macOS 입력기 목록이 아직 갱신되지 않았어요.")
        print("앱은 설치된 위치에 보존해요. 로그아웃 후 다시 로그인하고, 시스템 설정 → 키보드 → 텍스트 입력 → 편집에서 추가해 주세요.")
        break
    }
    if arguments[1] == "register" {
        for source in available { check(TISEnableInputSource(source), "입력기를 활성화하지 못했어요") }
    }
    print("두벌식 순아래를 등록했어요.")
    if sources().contains(where: { flag($0, kTISPropertyInputSourceIsEnabled) }) {
        print("입력 메뉴에서 두벌식 순아래를 선택해 주세요. macOS가 사용 승인을 요청하면 직접 승인해 주세요.")
    } else {
        print("시스템 설정 → 키보드 → 텍스트 입력 → 편집에서 두벌식 순아래를 추가하고, 사용 승인 요청을 확인해 주세요.")
    }
case "disable":
    if currentIdentifier().hasPrefix(bundleID) {
        fail("먼저 입력기를 ABC 또는 다른 한글 입력기로 바꾼 뒤 다시 실행해 주세요.")
    }
    for source in sources() { check(TISDisableInputSource(source), "입력 소스에서 제거하지 못했어요") }
case "trash":
    guard arguments.count == 3 else { fail("An app path is required") }
    let url = URL(fileURLWithPath: arguments[2])
    guard Bundle(url: url)?.bundleIdentifier == bundleID else { fail("This is not the Sunarae input method") }
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
