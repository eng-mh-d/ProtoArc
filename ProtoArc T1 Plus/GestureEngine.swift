//
//  GestureEngine.swift
//  ProtoArc T1 Plus
//
//  Consumes a stream of `TouchFrame`s and drives the `EventSynthesizer`.
//  Implements: single-finger tracking, tap-to-click, tap-and-drag,
//  two-finger scroll, two-finger tap (right click), pinch-to-zoom, and
//  three-finger swipes (Spaces / Mission Control / App Exposé).
//

import Foundation
import CoreGraphics
import QuartzCore

final class GestureEngine {
    private let synth: EventSynthesizer
    private let settings: TouchpadSettings

    init(synth: EventSynthesizer, settings: TouchpadSettings) {
        self.synth = synth
        self.settings = settings
    }

    // Per-finger last raw position, keyed by contactID.
    private var lastPositions: [Int: CGPoint] = [:]

    // Tap / gesture bookkeeping.
    private var touchStartTime: CFTimeInterval = 0
    private var touchStartCount = 0
    private var maxFingersDuringTouch = 0
    private var accumulatedMovement: CGFloat = 0      // pointer-frame movement, for tap rejection
    private var wasTouching = false

    // Double-tap-and-drag (tap-and-a-half): a quick tap followed by a second
    // touch that holds and slides => press-and-drag (e.g. moving sliders).
    // The drag is only *committed* once the second touch clearly intends to
    // drag (moves past `dragCommitTravel` or is held past a normal tap); until
    // then a quick lift stays a double click.
    private var lastTapLiftTime: CFTimeInterval = 0
    private var dragging = false
    private var pendingDoubleTapDrag = false
    /// Click streak for immediate select + double-tap (no deferred delay).
    private var selectClickStreak: Int = 0

    /// Optional sink for human-readable click/gesture events (shown in the log).
    var onLog: ((String) -> Void)?

    // Three-finger swipe accumulation.
    private var swipeAccum = CGPoint.zero
    private var swipeFired = false

    // Two-finger pinch baseline.
    private var lastPinchDistance: CGFloat? = nil

    // Physical clickpad button (bit in the touch report, Report ID 2).
    private var physicalButtonDown = false
    private var usedPhysicalButton = false
    private var physicalRightClick = false
    /// Finger on the pad when the physical left press began (the "hold" finger).
    private var physicalAnchorContactID: Int?
    private var physicalDragLogged = false
    // Physical left-click double-click detection (two fast presses = open).
    private var lastPhysicalLeftUpTime: CFTimeInterval = 0
    private var physicalLeftStreak: Int = 0

    // Discrete physical buttons from the mouse report (Report ID 1). The left
    // button is already covered by the clickpad/touch path, so here we act only
    // on the right and middle buttons (and log the left for diagnostics).
    private var mouseLeftDown = false
    private var mouseRightDown = false
    private var mouseMiddleDown = false

    // Currently tracked single finger (for stable cursor motion across re-touch).
    private var primarySingleID: Int?
    // Cursor only starts moving after the finger leaves a small dead zone, so a
    // plain tap never nudges the pointer.
    private var singleMoveAccum: CGFloat = 0
    private var pointerArmed = false

    // Tunables.
    private let tapMaxDuration: CFTimeInterval = 0.45 // a touch shorter than this can be a tap
    private let tapMaxMovement: CGFloat = 90          // raw units of total tap movement
    private let tapMoveCap: CGFloat = 20              // max per-frame movement counted toward a tap
    private let swipeThreshold: CGFloat = 220         // raw units of centroid travel
    private let pinchThreshold: CGFloat = 90          // raw units of distance change
    private let maxFrameJump: CGFloat = 500           // raw units; reject teleports
    private let jitterFloor: CGFloat = 1.5            // raw units; ignore micro-jitter
    private let moveDeadZone: CGFloat = 12            // raw units; tap vs. move threshold

    // Time of the last received report; used to detect lift-off via a gap.
    private var lastReportTime: CFTimeInterval = 0
    private let restGap: CFTimeInterval = 0.05        // > ~6 report intervals = lifted

    // Multi-finger touch detection log (2 or 3 contacts on the pad).
    private var previousFingerCount = 0
    private var twoTouchLogged = false
    private var threeTouchLogged = false
    private var firstFingerDownTime: CFTimeInterval = 0
    private var oneFingerSlideLogged = false
    /// True after a slide ended; prevents double-tap-drag arming on the next touch.
    private var lastGestureWasSlide = false

    /// Gap between two taps must fall in this window to count as double click (select ×2).
    private let doubleClickMinGap: CFTimeInterval = 0.010   // 10 ms
    private let doubleClickMaxGap: CFTimeInterval = 0.250   // 250 ms

    private func isDoubleClickGap(_ gap: CFTimeInterval) -> Bool {
        gap >= doubleClickMinGap && gap <= doubleClickMaxGap
    }

    /// Base gain so a full-pad swipe roughly crosses a typical display.
    private let basePointerGain = 0.62

    func process(frame: TouchFrame) {
        // Use active contacts (tipSwitch + inRange) so lift-off is detected when
        // the finger leaves the surface — same rule as the live touch UI.
        let touching = frame.activeTouching
        let now = CACurrentMediaTime()
        let count = touching.count

        // Bluetooth touchpads often stop reporting entirely when the finger is
        // lifted (no clean zero-contact frame). A gap longer than a few report
        // intervals therefore means the previous touch ended: drop all stale
        // baselines so a fresh touch never produces a jump-to-finger ("absolute")
        // motion. Without this, re-touching elsewhere moves the cursor by the
        // gap, which feels like a touchscreen.
        let gap = now - lastReportTime
        let liftTime = lastReportTime   // last sample while finger was still down
        lastReportTime = now
        if gap > restGap {
            if wasTouching {
                if count == 0 {
                    let wasSliding = pointerArmed || oneFingerSlideLogged
                        || singleMoveAccum >= moveDeadZone
                    if wasSliding {
                        if !oneFingerSlideLogged {
                            onLog?("touch & slide")
                            oneFingerSlideLogged = true
                        }
                        endSlideGesture()
                    } else {
                        let duration = liftTime - touchStartTime
                        let looksLikeTap = duration < tapMaxDuration
                            && singleMoveAccum < moveDeadZone
                            && accumulatedMovement < moveDeadZone
                        if looksLikeTap {
                            handleLiftOff(now: liftTime)
                        }
                    }
                    forceFreshSequence()
                } else {
                    // Finger still down — report pause only; don't tap or full reset.
                    partialRebaseline()
                }
            } else {
                forceFreshSequence()
            }
        }

        // Physical clickpad button: 1 finger (or none) = left (press/hold = drag),
        // 2+ fingers = right click. Takes priority over tap-to-click.
        if frame.button && !physicalButtonDown {
            physicalButtonDown = true
            usedPhysicalButton = true
            if count >= 2 {
                physicalRightClick = true
                synth.rightClick()
                onLog?("physical button → R-click")
            } else {
                physicalRightClick = false
                physicalAnchorContactID = touching.first?.contactID
                physicalDragLogged = false
                // Double-click detection for the physical LEFT button: if this
                // press closely follows the previous physical release, raise the
                // click state so two fast physical clicks open like a mouse
                // double click (3 = triple). The press is held so a press+move
                // still drags.
                let gap = now - lastPhysicalLeftUpTime
                if gap >= 0, isDoubleClickGap(gap) {
                    physicalLeftStreak += 1
                } else {
                    physicalLeftStreak = 1
                }
                let state = Int64(min(physicalLeftStreak, 3))
                synth.syncPointer()
                synth.pressLeft(clickState: state)
                onLog?(String(format: "physical L-press ×%d (gap %.0f ms, window 100–250 ms)",
                              state, gap * 1000))
            }
        } else if !frame.button && physicalButtonDown {
            physicalButtonDown = false
            if !physicalRightClick {
                synth.releaseLeft()
                lastPhysicalLeftUpTime = now
                onLog?("physical L-release")
            }
            physicalRightClick = false
            physicalAnchorContactID = nil
            physicalDragLogged = false
        }

        // Detect transition into "no fingers" -> evaluate taps & reset.
        if count == 0 {
            let wasSliding = pointerArmed || oneFingerSlideLogged
                || singleMoveAccum >= moveDeadZone
            if wasSliding { endSlideGesture() }

            if dragging {
                synth.releaseLeft()       // end a double-tap drag cleanly
                dragging = false
            } else if wasTouching && !wasSliding {
                handleLiftOff(now: now)
            }
            pendingDoubleTapDrag = false
            resetTransient()
            wasTouching = false
            usedPhysicalButton = false
            primarySingleID = nil
            previousFingerCount = 0
            twoTouchLogged = false
            threeTouchLogged = false
            oneFingerSlideLogged = false
            if !physicalButtonDown {
                synth.endPointerSession()
            }
            lastPositions.removeAll()
            return
        }

        if !wasTouching {
            // Fresh touch sequence begins.
            touchStartTime = now
            touchStartCount = count
            maxFingersDuringTouch = count
            if count >= 1 && count <= 3 { firstFingerDownTime = now }
            accumulatedMovement = 0
            swipeAccum = .zero
            swipeFired = false
            lastPinchDistance = nil
            singleMoveAccum = 0
            pointerArmed = false
            pendingDoubleTapDrag = false
            oneFingerSlideLogged = false

            // Second touch after a tap may become double-tap-drag (if enabled).
            // Never arm it right after a slide — that caused false drag on slide.
            if settings.doubleTapDrag, count == 1, !lastGestureWasSlide, lastTapLiftTime > 0 {
                let gap = now - lastTapLiftTime
                if isDoubleClickGap(gap) { pendingDoubleTapDrag = true }
            }
            lastGestureWasSlide = false
        }

        // A second finger cancels double-tap-drag, but not a physical-button drag.
        if count != 1 {
            if dragging, !physicalButtonDown {
                synth.releaseLeft()
                dragging = false
            }
            pendingDoubleTapDrag = false
        }

        wasTouching = true
        maxFingersDuringTouch = max(maxFingersDuringTouch, count)

        logMultiFingerTouchIfNeeded(touching: touching, count: count, now: now)

        // Physical left held: move the cursor with any finger (e.g. hold button
        // with one finger, drag with another) for drag-and-drop.
        if physicalButtonDown, !physicalRightClick {
            handlePhysicalDrag(touching, now: now)
        } else {
            switch count {
            case 1:
                handleSingle(touching[0], now: now)
            case 2:
                handleDouble(touching, now: now)
            default:
                handleTriplePlus(touching)
            }
        }

        // Remember positions for next-frame deltas.
        lastPositions = Dictionary(uniqueKeysWithValues: touching.map { ($0.contactID, CGPoint(x: $0.rawX, y: $0.rawY)) })
    }

    // MARK: - Physical mouse buttons (Report ID 1)

    /// Handle the discrete physical buttons reported on the standard mouse
    /// report. Right and middle fire a click on press; left is logged only
    /// (it is already produced by the clickpad path to avoid a double event).
    func physicalMouseButtons(_ b: MouseButtons) {
        if b.right != mouseRightDown {
            mouseRightDown = b.right
            if b.right { synth.rightClick(); onLog?("physical RIGHT button → R-click") }
        }
        if b.middle != mouseMiddleDown {
            mouseMiddleDown = b.middle
            if b.middle { synth.middleClick(); onLog?("physical MIDDLE button → M-click") }
        }
        if b.left != mouseLeftDown {
            mouseLeftDown = b.left
            onLog?(b.left ? "physical LEFT button down (report 1)"
                          : "physical LEFT button up (report 1)")
        }
    }

    // MARK: - Multi-finger touch log

    /// Log once when 2 or 3 fingers are on the pad — together or staggered.
    private func logMultiFingerTouchIfNeeded(touching: [TouchContact], count: Int, now: CFTimeInterval) {
        if count == 1, previousFingerCount == 0 {
            firstFingerDownTime = now
        }

        let ids = touching.map { $0.contactID }.sorted()
        let idText = ids.map(String.init).joined(separator: ", ")
        let gapMs = max(0, (now - firstFingerDownTime) * 1000)
        let simultaneous = previousFingerCount == 0

        if count == 2, !twoTouchLogged {
            if simultaneous {
                onLog?("2 touch [\(idText)] simultaneous")
            } else {
                onLog?(String(format: "2 touch [%@] gap %.0f ms", idText, gapMs))
            }
            twoTouchLogged = true
        }

        if count == 3, !threeTouchLogged {
            if simultaneous {
                onLog?("3 touch [\(idText)] simultaneous")
            } else {
                onLog?(String(format: "3 touch [%@] gap %.0f ms", idText, gapMs))
            }
            threeTouchLogged = true
        }

        previousFingerCount = count
    }

    // MARK: - Single finger: move + drag

    private func handleSingle(_ c: TouchContact, now: CFTimeInterval) {
        // When the tracked finger changes (lift + re-touch, or finger switch),
        // re-baseline without moving so the cursor keeps its last position
        // instead of jumping to a delta from a stale contact.
        if primarySingleID != c.contactID {
            primarySingleID = c.contactID
            return
        }

        // As the finger leaves the surface the hardware may briefly report odd
        // positions; activeTouching already drops out-of-range contacts.
        guard let prev = lastPositions[c.contactID] else { return }
        let dxRaw = c.rawX - prev.x
        let dyRaw = c.rawY - prev.y

        let dist = hypot(dxRaw, dyRaw)

        // Ignore implausible single-frame jumps (finger relanded elsewhere, or a
        // reused contact ID): just re-baseline, don't teleport the cursor.
        if dist > maxFrameJump { return }

        // Reject micro-jitter so a resting / lightly-pressed finger stays still.
        if dist < jitterFloor { return }

        // Cap each frame's contribution to the tap-movement total so a single
        // noisy sample can't push a stationary tap over the "this was a drag"
        // threshold (a genuine drag accumulates many capped frames instead).
        accumulatedMovement += min(dist, tapMoveCap)

        // Second touch in the double-tap window + slide → hold left button and drag
        // (drag-and-drop). Quick second lift without sliding stays a double click.
        if settings.doubleTapDrag, pendingDoubleTapDrag, !dragging {
            singleMoveAccum += dist
            if singleMoveAccum < moveDeadZone { return }
            pendingDoubleTapDrag = false
            dragging = true
            pointerArmed = true
            synth.syncPointer()
            synth.pressLeft()
            onLog?("double-tap & slide drag")
        }

        // Dead zone: a plain tap (tiny movement) must not move the pointer.
        // Only start tracking once the finger has clearly moved. A held physical
        // button bypasses the dead zone so dragging starts immediately.
        if !pointerArmed {
            if physicalButtonDown {
                pointerArmed = true
            } else if settings.doubleTapDrag, pendingDoubleTapDrag {
                // Waiting for enough movement to commit the double-tap drag.
                return
            } else {
                singleMoveAccum += dist
                if singleMoveAccum < moveDeadZone { return }
                pointerArmed = true
                synth.syncPointer()
                if !oneFingerSlideLogged {
                    onLog?("touch & slide")
                    oneFingerSlideLogged = true
                }
            }
        }

        // Pointer acceleration: faster motion travels disproportionately farther.
        let speed = dist
        let accel = 1.0 + min(speed / 12.0, 6.0)
        let gain = basePointerGain * settings.pointerSpeed * accel

        synth.moveBy(dx: Double(dxRaw) * gain, dy: Double(dyRaw) * gain)
    }

    // MARK: - Physical button + finger drag (drag-and-drop)

    /// While the physical left button is held, move the cursor with one or more
    /// fingers. If a second finger lands, it can slide while the first stays put
    /// (hold button + drag with another finger).
    private func handlePhysicalDrag(_ touching: [TouchContact], now: CFTimeInterval) {
        pointerArmed = true

        if touching.count == 1 {
            handleSingle(touching[0], now: now)
            return
        }

        // Prefer fingers other than the anchor (the one down when the button pressed).
        var movers = touching
        if let anchor = physicalAnchorContactID {
            let others = touching.filter { $0.contactID != anchor }
            if !others.isEmpty { movers = others }
        }

        var sumdx: CGFloat = 0, sumdy: CGFloat = 0, n: CGFloat = 0
        for c in movers {
            guard let prev = lastPositions[c.contactID] else { continue }
            sumdx += c.rawX - prev.x
            sumdy += c.rawY - prev.y
            n += 1
        }
        guard n > 0 else { return }

        let dxRaw = sumdx / n
        let dyRaw = sumdy / n
        let dist = hypot(dxRaw, dyRaw)
        if dist < jitterFloor { return }
        if dist > maxFrameJump { return }

        if !physicalDragLogged {
            onLog?("physical button + finger drag")
            physicalDragLogged = true
        }

        let speed = dist
        let accel = 1.0 + min(speed / 12.0, 6.0)
        let gain = basePointerGain * settings.pointerSpeed * accel
        synth.moveBy(dx: Double(dxRaw) * gain, dy: Double(dyRaw) * gain)
    }

    // MARK: - Two fingers: scroll, pinch, right-click

    private func handleDouble(_ touching: [TouchContact], now: CFTimeInterval) {
        let a = touching[0], b = touching[1]
        guard let pa = lastPositions[a.contactID], let pb = lastPositions[b.contactID] else {
            lastPinchDistance = hypot(a.rawX - b.rawX, a.rawY - b.rawY)
            return
        }

        let curDistance = hypot(a.rawX - b.rawX, a.rawY - b.rawY)
        let prevDistance = hypot(pa.x - pb.x, pa.y - pb.y)
        let distanceDelta = curDistance - prevDistance

        // Centroid movement (for scroll).
        let curCx = (a.rawX + b.rawX) / 2, curCy = (a.rawY + b.rawY) / 2
        let prevCx = (pa.x + pb.x) / 2, prevCy = (pa.y + pb.y) / 2
        let cdx = curCx - prevCx, cdy = curCy - prevCy
        let centroidMove = hypot(cdx, cdy)

        accumulatedMovement += centroidMove + abs(distanceDelta)

        // Pinch dominates when the inter-finger distance changes more than the
        // pair translates together.
        if settings.enableGestures, abs(distanceDelta) > centroidMove * 1.5 {
            if let baseline = lastPinchDistance {
                let total = curDistance - baseline
                if abs(total) > pinchThreshold {
                    synth.perform(total > 0 ? .zoomIn : .zoomOut)
                    lastPinchDistance = curDistance
                }
            } else {
                lastPinchDistance = curDistance
            }
            return
        }

        guard settings.twoFingerScroll else { return }
        let scale = 0.5 * settings.scrollSpeed
        let dir: Double = settings.naturalScrolling ? 1.0 : -1.0
        synth.scroll(dx: Double(-cdx) * scale * dir, dy: Double(cdy) * scale * dir)
    }

    // MARK: - Three+ fingers: swipes

    private func handleTriplePlus(_ touching: [TouchContact]) {
        guard settings.enableGestures, !swipeFired else { return }

        // Average per-finger delta = robust centroid translation.
        var sumdx: CGFloat = 0, sumdy: CGFloat = 0, n: CGFloat = 0
        for c in touching {
            if let prev = lastPositions[c.contactID] {
                sumdx += c.rawX - prev.x
                sumdy += c.rawY - prev.y
                n += 1
            }
        }
        guard n > 0 else { return }
        swipeAccum.x += sumdx / n
        swipeAccum.y += sumdy / n

        if abs(swipeAccum.x) > swipeThreshold || abs(swipeAccum.y) > swipeThreshold {
            if abs(swipeAccum.x) > abs(swipeAccum.y) {
                let goingRight = swipeAccum.x > 0
                switch settings.horizontalSwipe {
                case .spaces:
                    synth.perform(goingRight ? .spaceRight : .spaceLeft)
                case .tabs:
                    synth.perform(goingRight ? .tabNext : .tabPrev)
                case .windows:
                    synth.perform(goingRight ? .windowNext : .windowPrev)
                }
            } else {
                synth.perform(swipeAccum.y > 0 ? .appExpose : .missionControl)
            }
            swipeFired = true
        }
    }

    // MARK: - Lift-off: decide taps

    private func handleLiftOff(now: CFTimeInterval) {
        // A physical click already produced the button event; don't double it.
        guard !usedPhysicalButton else { return }

        let duration = now - touchStartTime
        let wasSliding = pointerArmed || oneFingerSlideLogged
            || singleMoveAccum >= moveDeadZone
            || accumulatedMovement >= moveDeadZone
        let wasTap = duration < tapMaxDuration && !wasSliding && accumulatedMovement < tapMaxMovement
        guard wasTap else {
            if maxFingersDuringTouch == 1 && !usedPhysicalButton {
                if wasSliding {
                    if !oneFingerSlideLogged {
                        onLog?("touch & slide")
                        oneFingerSlideLogged = true
                    }
                    endSlideGesture()
                } else if !wasSliding {
                    onLog?(String(format: "tap rejected: dur %.0f ms (max %.0f), move %.0f (max %.0f)",
                                  duration * 1000, tapMaxDuration * 1000,
                                  accumulatedMovement, tapMaxMovement))
                }
            } else if maxFingersDuringTouch != 1 {
                onLog?(String(format: "tap rejected: dur %.0f ms (max %.0f), move %.0f (max %.0f)",
                              duration * 1000, tapMaxDuration * 1000,
                              accumulatedMovement, tapMaxMovement))
            }
            return
        }

        switch maxFingersDuringTouch {
        case 1:
            performSelect()
            lastTapLiftTime = now
        case 2:
            performTouchGesture(settings.twoFingerTouchGesture, fingers: 2)
        case 3:
            guard !swipeFired else { break }
            performTouchGesture(settings.threeFingerTouchGesture, fingers: 3)
        default:
            break
        }
    }

    /// Called when a slide ends so the next touch is a clean tap (not double-tap-drag).
    private func endSlideGesture() {
        lastGestureWasSlide = true
        lastTapLiftTime = 0
        pendingDoubleTapDrag = false
        selectClickStreak = 0
        if dragging {
            synth.releaseLeft()
            dragging = false
        }
    }

    /// Quick one-finger tap (no swipe/slide): select immediately (no delay).
    /// Two fast taps use click-state 2 for a native double click.
    private func performSelect() {
        onLog?("touch")

        switch settings.oneFingerTap {
        case .none:
            onLog?("1 touch → no action")
        case .leftClick:
            let gapMs = lastTapLiftTime > 0 ? (touchStartTime - lastTapLiftTime) * 1000 : 0
            let isDouble = lastTapLiftTime > 0 && isDoubleClickGap(touchStartTime - lastTapLiftTime)
            let state: Int64 = isDouble ? 2 : 1
            selectClickStreak = Int(state)
            synth.leftClick(clickState: state)
            onLog?(String(format: "select ×%d (gap %.0f ms, window 100–250 ms)", state, gapMs))
        case .rightClick:
            synth.rightClick()
            onLog?("1 touch → R-click")
        case .middleClick:
            synth.middleClick()
            onLog?("1 touch → M-click")
        case .doubleClick:
            synth.doubleClick()
            onLog?("1 touch → double L-click")
        }
    }

    /// Execute a touch-only gesture (2- or 3-finger tap). Physical button
    /// presses never reach here — `usedPhysicalButton` is checked in lift-off.
    private func performTouchGesture(_ action: TouchGestureAction, fingers: Int) {
        switch action {
        case .none:
            onLog?("\(fingers)-finger touch → no action")
        case .leftClick:
            synth.leftClick(clickState: 1)
            onLog?("\(fingers)-finger touch → L-click")
        case .rightClick:
            synth.rightClick()
            onLog?("\(fingers)-finger touch → R-click")
        case .middleClick:
            synth.middleClick()
            onLog?("\(fingers)-finger touch → M-click")
        case .doubleClick:
            synth.doubleClick()
            onLog?("\(fingers)-finger touch → double L-click")
        case .missionControl:
            synth.perform(.missionControl)
            onLog?("\(fingers)-finger touch → Mission Control")
        case .appExpose:
            synth.perform(.appExpose)
            onLog?("\(fingers)-finger touch → App Exposé")
        case .spaceLeft:
            synth.perform(.spaceLeft)
            onLog?("\(fingers)-finger touch → Space left")
        case .spaceRight:
            synth.perform(.spaceRight)
            onLog?("\(fingers)-finger touch → Space right")
        case .zoomIn:
            synth.perform(.zoomIn)
            onLog?("\(fingers)-finger touch → Zoom in")
        case .zoomOut:
            synth.perform(.zoomOut)
            onLog?("\(fingers)-finger touch → Zoom out")
        case .tabPrev:
            synth.perform(.tabPrev)
            onLog?("\(fingers)-finger touch → Tab prev")
        case .tabNext:
            synth.perform(.tabNext)
            onLog?("\(fingers)-finger touch → Tab next")
        case .windowPrev:
            synth.perform(.windowPrev)
            onLog?("\(fingers)-finger touch → Window prev")
        case .windowNext:
            synth.perform(.windowNext)
            onLog?("\(fingers)-finger touch → Window next")
        }
    }

    private func resetTransient() {
        accumulatedMovement = 0
        swipeAccum = .zero
        swipeFired = false
        lastPinchDistance = nil
    }

    /// Report gap while the finger is still down: refresh baselines without tap or full reset.
    private func partialRebaseline() {
        lastPositions.removeAll()
        primarySingleID = nil
        pendingDoubleTapDrag = false
    }

    /// Clear stuck drag / button state (e.g. after clicking the menu bar with the touchpad).
    func unstickPointer() {
        synth.forceReleaseLeft()
        synth.endPointerSession()
        dragging = false
        pendingDoubleTapDrag = false
        pointerArmed = false
        singleMoveAccum = 0
        oneFingerSlideLogged = false
        partialRebaseline()
    }

    /// Drop every per-touch baseline so the next frame starts a clean sequence
    /// with no movement (used when a report gap implies the finger was lifted).
    private func forceFreshSequence() {
        // A report gap means everything was lifted, so release any held button
        // to avoid a stuck/"frozen" pointer.
        synth.releaseLeft()
        dragging = false
        pendingDoubleTapDrag = false
        physicalButtonDown = false
        physicalRightClick = false
        usedPhysicalButton = false
        physicalAnchorContactID = nil
        physicalDragLogged = false
        wasTouching = false
        primarySingleID = nil
        pointerArmed = false
        singleMoveAccum = 0
        lastPositions.removeAll()
        previousFingerCount = 0
        twoTouchLogged = false
        threeTouchLogged = false
        oneFingerSlideLogged = false
        synth.endPointerSession()
    }
}
