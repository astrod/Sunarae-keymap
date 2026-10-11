import IOKit

/// Watches device arrival, not keyboard input. No HID device is opened.
final class KeyboardConnectionObserver {
    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var pending: DispatchWorkItem?
    private let changed: () -> Void

    init(changed: @escaping () -> Void) {
        self.changed = changed
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let result = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification,
            IOServiceMatching("IOHIDEventService"), { context, iterator in
                guard let context else { return }
                Unmanaged<KeyboardConnectionObserver>.fromOpaque(context).takeUnretainedValue().arrived(iterator)
            }, Unmanaged.passUnretained(self).toOpaque(), &iterator)
        if result == KERN_SUCCESS { arrived(iterator) }
    }

    private func arrived(_ iterator: io_iterator_t) {
        var found = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            found = true; IOObjectRelease(service)
        }
        guard found else { return }
        // Let the event system publish the new service before reading mappings.
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.changed() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    deinit {
        pending?.cancel()
        if iterator != 0 { IOObjectRelease(iterator) }
        if let port { IONotificationPortDestroy(port) }
    }
}
