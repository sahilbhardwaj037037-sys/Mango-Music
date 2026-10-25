import AppKit
import CoreAudio

@MainActor
final class NativePlaybackLifecycle: PlaybackLifecycleMonitoring {
    private var observers: [NSObjectProtocol] = []
    private var audioListener: AudioObjectPropertyListenerBlock?
    var isMonitoringOutput: Bool { audioListener != nil }
    private(set) var lastRemovalStatus: OSStatus?
    private var lastOutput: AudioDeviceID?
    private var registration = UUID()
    private var handler: (@MainActor @Sendable (PlaybackInterruption) -> Void)?
    private var address: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func outputDevice() -> AudioDeviceID? {
        var value = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    func activate(_ handler: @escaping @MainActor @Sendable (PlaybackInterruption) -> Void) {
        guard self.handler == nil else { return }
        self.handler = handler
        registration = UUID(); let epoch = registration
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, PlaybackInterruption.sleep),
                               (NSWorkspace.didWakeNotification, PlaybackInterruption.wake)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // NotificationCenter's explicit main queue establishes this executor.
                MainActor.assumeIsolated { if self?.registration == epoch { self?.handler?(reason) } }
            })
        }
        lastOutput = Self.outputDevice()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.registration == epoch, self.handler != nil, let output = Self.outputDevice(), output != self.lastOutput else { return }
                self.lastOutput = output; self.handler?(.outputChanged)
            }
        }
        var address = address
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
            audioListener = listener
        }
    }
    func deactivate() {
        handler = nil; registration = UUID()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        if let audioListener {
            var address = address
            lastRemovalStatus = AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, audioListener)
        }
        audioListener = nil; lastOutput = nil
    }
}
