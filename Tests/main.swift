import AppKit

_ = NSApplication.shared
for (keys, expected) in sunaraeExamples { expect(compose(keys), expected, keys) }
runSessionChecks()
runCompatibilityChecks()
runReentrancyChecks()
runEscapeChecks()
runSunaraeChecks()
runEditingChecks()
print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
