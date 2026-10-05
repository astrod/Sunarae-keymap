import AppKit

_ = NSApplication.shared
for (keys, expected) in sunaraeExamples { expect(compose(keys), expected, keys) }
runSessionChecks()
runDeliveryChecks()
runSpaceChecks()
runEscapeChecks()
runSunaraeChecks()
runEditingChecks()
print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
