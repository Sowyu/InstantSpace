import ApplicationServices
import CoreFoundation
import Foundation

enum SpaceDirection {
    case left
    case right
}

final class SpaceEngine {
    static let shared = SpaceEngine()

    private enum Defaults {
        static let animationEnabledKey = "animationEnabled"
        static let animationSpeedKey = "animationSpeed"
        static let defaultAnimationEnabled = true
        static let defaultAnimationSpeed = 100.0
    }

    private let instantGestureSpeed = 60000.0
    private let minimumAnimatedGestureSpeed = 1500.0
    private let maximumAnimatedGestureSpeed = 42000.0
    private let minimumAnimationDuration = 0.045
    private let maximumAnimationDuration = 0.28

    private let kCGSEventTypeField = CGEventField(rawValue: 55)!
    private let kCGEventGestureHIDType = CGEventField(rawValue: 110)!
    private let kCGEventGestureSwipeMotion = CGEventField(rawValue: 123)!
    private let kCGEventGestureSwipeProgress = CGEventField(rawValue: 124)!
    private let kCGEventGestureSwipeVelocityX = CGEventField(rawValue: 129)!
    private let kCGEventGestureSwipeVelocityY = CGEventField(rawValue: 130)!
    private let kCGEventGesturePhase = CGEventField(rawValue: 132)!

    private let kIOHIDEventTypeDockSwipe: Int32 = 23
    private let kCGSEventDockControl: Int32 = 30
    private let kCGGestureMotionHorizontal: Int32 = 1
    private let dockControlEventType = CGEventType(rawValue: 30)!
    private let syntheticGestureMarker: Int64 = 0x5350414345

    private enum GesturePhase: Int32 {
        case began = 1
        case changed = 2
        case ended = 4
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var predictions: [String: UInt32] = [:]
    private var physicalSwipeHandled = false
    private var physicalSwipeDirection: SpaceDirection?
    private var physicalSwipeProgress: Double = 0.0
    private var physicalSwipeBlocked = false
    private var animationGeneration = 0

    private init() {
        UserDefaults.standard.register(defaults: [
            Defaults.animationEnabledKey: Defaults.defaultAnimationEnabled,
            Defaults.animationSpeedKey: Defaults.defaultAnimationSpeed,
        ])
    }

    var isRunning: Bool {
        guard let eventTap else { return false }
        return CFMachPortIsValid(eventTap)
    }

    var animationEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: Defaults.animationEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Defaults.animationEnabledKey)
            UserDefaults.standard.synchronize()
            if !newValue {
                cancelAnimatedSwitch()
            }
        }
    }

    var animationSpeed: Double {
        get {
            Self.clampAnimationSpeed(UserDefaults.standard.double(forKey: Defaults.animationSpeedKey))
        }
        set {
            UserDefaults.standard.set(Self.clampAnimationSpeed(newValue), forKey: Defaults.animationSpeedKey)
            UserDefaults.standard.synchronize()
        }
    }

    func loadSavedSettings() {
        _ = animationEnabled
        _ = animationSpeed
    }

    func start() -> Bool {
        if let eventTap {
            if CFMachPortIsValid(eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                return true
            }
            stop()
        }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)
                | (1 << dockControlEventType.rawValue)
                | (1 << CGEventType.tapDisabledByTimeout.rawValue)
                | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        )

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let engine = Unmanaged<SpaceEngine>.fromOpaque(userInfo).takeUnretainedValue()
                    return engine.handleEvent(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
    }

    func resetPredictions() {
        predictions.removeAll()
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == dockControlEventType {
            return handleDockSwipe(event: event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        return handleKeyDown(event: event)
    }

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        guard flags.contains(.maskControl), !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate), !flags.contains(.maskShift)
        else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let direction: SpaceDirection?
        switch keyCode {
        case 123:
            direction = .left
        case 124:
            direction = .right
        default:
            direction = nil
        }

        guard let direction else {
            return Unmanaged.passUnretained(event)
        }

        _ = switchSpace(direction)
        return nil
    }

    private func handleDockSwipe(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isHorizontalDockSwipe(event) else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticGestureMarker {
            return Unmanaged.passUnretained(event)
        }

        let phase = GesturePhase(rawValue: Int32(event.getIntegerValueField(kCGEventGesturePhase)))

        guard animationEnabled else {
            return handleInstantDockSwipe(event: event, phase: phase)
        }

        switch phase {
        case .began:
            physicalSwipeDirection = swipeDirection(from: event)
            physicalSwipeProgress = abs(event.getDoubleValueField(kCGEventGestureSwipeProgress))
            if let direction = physicalSwipeDirection, shouldBlockSwitch(direction) {
                physicalSwipeBlocked = true
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .changed:
            if physicalSwipeBlocked {
                return nil
            }

            if let direction = swipeDirection(from: event) {
                physicalSwipeDirection = direction
                if shouldBlockSwitch(direction) {
                    physicalSwipeBlocked = true
                    return nil
                }
            }
            physicalSwipeProgress = max(
                physicalSwipeProgress,
                abs(event.getDoubleValueField(kCGEventGestureSwipeProgress))
            )
            return Unmanaged.passUnretained(event)

        case .ended:
            let direction = physicalSwipeDirection ?? swipeDirection(from: event)
            let progress = max(
                physicalSwipeProgress,
                abs(event.getDoubleValueField(kCGEventGestureSwipeProgress))
            )
            physicalSwipeDirection = nil
            physicalSwipeProgress = 0.0
            let blocked = physicalSwipeBlocked
            physicalSwipeBlocked = false

            if blocked {
                return nil
            }

            guard let direction else {
                return Unmanaged.passUnretained(event)
            }

            completeHeldSwipe(direction: direction, from: progress)
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleInstantDockSwipe(event: CGEvent, phase: GesturePhase?) -> Unmanaged<CGEvent>? {
        if phase == .ended {
            physicalSwipeHandled = false
            return nil
        }

        guard !physicalSwipeHandled, let direction = swipeDirection(from: event) else {
            return nil
        }

        physicalSwipeHandled = true

        guard !shouldBlockSwitch(direction) else {
            return nil
        }

        _ = switchSpace(direction, animated: false)
        return nil
    }

    private func cancelAnimatedSwitch() {
        animationGeneration &+= 1
        physicalSwipeHandled = false
        physicalSwipeDirection = nil
        physicalSwipeProgress = 0.0
        physicalSwipeBlocked = false
    }

    private func isHorizontalDockSwipe(_ event: CGEvent) -> Bool {
        let eventType = event.getIntegerValueField(kCGSEventTypeField)
        let hidType = event.getIntegerValueField(kCGEventGestureHIDType)
        let motion = event.getIntegerValueField(kCGEventGestureSwipeMotion)

        return eventType == Int64(kCGSEventDockControl)
            && hidType == Int64(kIOHIDEventTypeDockSwipe)
            && motion == Int64(kCGGestureMotionHorizontal)
    }

    private func swipeDirection(from event: CGEvent) -> SpaceDirection? {
        let velocity = event.getDoubleValueField(kCGEventGestureSwipeVelocityX)
        if velocity > 0 { return .right }
        if velocity < 0 { return .left }

        let progress = event.getDoubleValueField(kCGEventGestureSwipeProgress)
        if progress > 0 { return .right }
        if progress < 0 { return .left }

        return nil
    }

    private func completeHeldSwipe(direction: SpaceDirection, from progress: Double) {
        animationGeneration &+= 1
        let generation = animationGeneration
        let right = direction == .right
        let sign: Float = right ? 1.0 : -1.0
        let velocity = right ? animatedGestureSpeed : -animatedGestureSpeed
        let startProgress = min(0.98, max(0.02, progress))
        let remaining = max(0.02, 1.0 - startProgress)
        let steps = max(3, Int(ceil(14.0 * remaining)))
        let duration = max(0.035, animationDuration * remaining)
        let interval = duration / Double(steps)

        for step in 1...steps {
            let delay = interval * Double(step)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.animationGeneration == generation else { return }

                if step == steps {
                    _ = self.postDockSwipe(phase: .ended, progress: sign, velocity: velocity)
                } else {
                    let fraction = Double(step) / Double(steps)
                    let progress = startProgress + ((1.0 - startProgress) * fraction)
                    _ = self.postDockSwipe(phase: .changed, progress: sign * Float(progress), velocity: velocity)
                }
            }
        }
    }

    private func shouldBlockSwitch(_ direction: SpaceDirection) -> Bool {
        var info = SpaceInfo()
        guard loadSpaceInfo(&info) else { return false }
        let current = predictions[info.displayID] ?? info.currentIndex
        return shouldBlockSwitch(info: info, current: current, direction: direction)
    }

    @discardableResult
    func switchSpace(_ direction: SpaceDirection, animated: Bool? = nil) -> Bool {
        var info = SpaceInfo()
        if loadSpaceInfo(&info) {
            let current = predictions[info.displayID] ?? info.currentIndex
            let target = direction == .left ? current &- 1 : current &+ 1

            if shouldBlockSwitch(info: info, current: current, direction: direction) {
                return false
            }

            guard postSwitchGesture(direction, animated: animated ?? animationEnabled) else { return false }
            predictions[info.displayID] = target
            return true
        }

        return postSwitchGesture(direction, animated: animated ?? animationEnabled)
    }

    private func shouldBlockSwitch(info: SpaceInfo, current: UInt32, direction: SpaceDirection) -> Bool {
        if info.spaceCount == 0 { return true }
        if direction == .left { return current == 0 }
        return current + 1 >= info.spaceCount
    }

    private func postSwitchGesture(_ direction: SpaceDirection, animated: Bool) -> Bool {
        let right = direction == .right
        let progress = right ? Float.leastNormalMagnitude : -Float.leastNormalMagnitude
        let velocity = right ? instantGestureSpeed : -instantGestureSpeed

        guard animated else {
            return postDockSwipe(phase: .began, progress: progress, velocity: velocity)
                && postDockSwipe(phase: .changed, progress: progress, velocity: velocity)
                && postDockSwipe(phase: .ended, progress: progress, velocity: velocity)
        }

        return postAnimatedSwitchGesture(direction)
    }

    private func postAnimatedSwitchGesture(_ direction: SpaceDirection) -> Bool {
        animationGeneration &+= 1
        let generation = animationGeneration
        let right = direction == .right
        let sign: Float = right ? 1.0 : -1.0
        let speed = animatedGestureSpeed
        let velocity = right ? speed : -speed
        let steps = 14
        let interval = animationDuration / Double(steps)

        guard postDockSwipe(phase: .began, progress: sign * Float.leastNormalMagnitude, velocity: velocity) else {
            return false
        }

        for step in 1...steps {
            let delay = interval * Double(step)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.animationGeneration == generation else { return }

                if step == steps {
                    _ = self.postDockSwipe(phase: .ended, progress: sign, velocity: velocity)
                } else {
                    let progress = sign * Float(Double(step) / Double(steps))
                    _ = self.postDockSwipe(phase: .changed, progress: progress, velocity: velocity)
                }
            }
        }

        return true
    }

    private var animatedGestureSpeed: Double {
        let normalized = animationSpeed / 100.0
        return minimumAnimatedGestureSpeed
            + ((maximumAnimatedGestureSpeed - minimumAnimatedGestureSpeed) * normalized)
    }

    private var animationDuration: Double {
        let normalized = animationSpeed / 100.0
        return maximumAnimationDuration
            - ((maximumAnimationDuration - minimumAnimationDuration) * normalized)
    }

    private static func clampAnimationSpeed(_ speed: Double) -> Double {
        min(100.0, max(1.0, speed))
    }

    private func postDockSwipe(phase: GesturePhase, progress: Float, velocity: Double) -> Bool {
        guard let event = CGEvent(source: nil) else { return false }

        event.setIntegerValueField(kCGSEventTypeField, value: Int64(kCGSEventDockControl))
        event.setIntegerValueField(.eventSourceUserData, value: syntheticGestureMarker)
        event.setIntegerValueField(kCGEventGestureHIDType, value: Int64(kIOHIDEventTypeDockSwipe))
        event.setIntegerValueField(kCGEventGesturePhase, value: Int64(phase.rawValue))
        event.setDoubleValueField(kCGEventGestureSwipeProgress, value: Double(progress))
        event.setIntegerValueField(kCGEventGestureSwipeMotion, value: Int64(kCGGestureMotionHorizontal))
        event.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: velocity)
        event.setDoubleValueField(kCGEventGestureSwipeVelocityY, value: velocity)

        event.post(tap: .cgSessionEventTap)
        return true
    }

    private struct SpaceInfo {
        var currentIndex: UInt32 = 0
        var spaceCount: UInt32 = 0
        var displayID: String = ""
    }

    private typealias CGSConnectionID = Int32
    private typealias CGSSpaceID = UInt64
    private typealias MainConnectionFn = @convention(c) () -> CGSConnectionID
    private typealias GetActiveSpaceFn = @convention(c) (CGSConnectionID) -> CGSSpaceID
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (CGSConnectionID, CFString?) -> Unmanaged<CFArray>?

    private lazy var cgsMainConnection: MainConnectionFn? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_LAZY), "CGSMainConnectionID") else { return nil }
        return unsafeBitCast(symbol, to: MainConnectionFn.self)
    }()

    private lazy var cgsGetActiveSpace: GetActiveSpaceFn? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_LAZY), "CGSGetActiveSpace") else { return nil }
        return unsafeBitCast(symbol, to: GetActiveSpaceFn.self)
    }()

    private lazy var cgsCopyManagedDisplaySpaces: CopyManagedDisplaySpacesFn? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_LAZY), "CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyManagedDisplaySpacesFn.self)
    }()

    private func loadSpaceInfo(_ info: inout SpaceInfo) -> Bool {
        guard let cgsMainConnection, let cgsGetActiveSpace, let cgsCopyManagedDisplaySpaces else {
            return false
        }

        let mainConnection = cgsMainConnection()
        guard mainConnection != 0 else { return false }

        let activeSpace = cgsGetActiveSpace(mainConnection)
        guard activeSpace != 0 else { return false }

        guard let displays = cgsCopyManagedDisplaySpaces(mainConnection, nil)?.takeRetainedValue() else {
            return false
        }

        guard let displayDict = (displays as? [NSDictionary])?.first else {
            return false
        }

        if let identifier = displayDict["Display Identifier"] as? String {
            info.displayID = identifier
        }

        guard let spaces = displayDict["Spaces"] as? [NSDictionary] else {
            return false
        }

        var displayActiveSpace: CGSSpaceID = 0
        if let currentSpace = displayDict["Current Space"] as? NSDictionary,
           let idNumber = currentSpace["id64"] as? NSNumber
        {
            displayActiveSpace = idNumber.uint64Value
        }

        let targetActiveSpace = displayActiveSpace != 0 ? displayActiveSpace : activeSpace

        var totalSpaces: UInt32 = 0
        var activeIndex: UInt32 = 0
        var foundActive = false

        for space in spaces {
            guard let idNumber = space["id64"] as? NSNumber else { continue }
            let candidate = idNumber.uint64Value
            if !foundActive && candidate == targetActiveSpace {
                activeIndex = totalSpaces
                foundActive = true
            }
            totalSpaces &+= 1
        }

        guard totalSpaces > 0, foundActive else { return false }

        info.spaceCount = totalSpaces
        info.currentIndex = activeIndex
        return true
    }
}
