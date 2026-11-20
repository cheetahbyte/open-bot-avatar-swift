import XCTest
@testable import OpenBotAvatar

final class StateTests: XCTestCase {
    private let seed: UInt32 = 12345

    private func pose(_ step: AvatarAnimator.Step, time: Double, reducedMotion: Bool = false) -> AvatarPose {
        AvatarPose(.init(
            seed: seed, time: time, mood: step.mood, gaze: step.gaze, reducedMotion: reducedMotion,
            state: step.state, stateAge: step.stateAge))
    }

    func testStatesAndMoodsAreIndependentAndLegacyConstructorsStillWork() throws {
        XCTAssertEqual(AvatarState.allCases.map(\.rawValue), ["idle", "thinking", "working", "waiting", "blocked", "done"])
        XCTAssertEqual(AvatarMood.allCases.map(\.rawValue), ["neutral", "happy"])
        let legacyThinking = try XCTUnwrap(AvatarMood(rawValue: "thinking"))
        let old = AvatarPose(.init(seed: seed, time: 2, mood: .settled(legacyThinking)))
        let current = AvatarPose(.init(seed: seed, time: 2, state: .thinking))
        XCTAssertEqual(old, current)
        let explicit = AvatarPose(.init(seed: seed, time: 2, mood: .settled(legacyThinking), state: .blocked))
        XCTAssertEqual(explicit.bang, 1, "An explicit state wins over legacy thinking")
        XCTAssertEqual(explicit.dots, 0)
        let happyThinking = AvatarPose(.init(seed: seed, time: 2, mood: .settled(.happy), state: .thinking))
        XCTAssertEqual(happyThinking.eyes.arc, 1)
        XCTAssertEqual(happyThinking.dots, 1)
        XCTAssertEqual(happyThinking.lift, current.lift, "Happy does not replace the thinking state's motion")
    }

    func testDoneMountsAtRestAndEnteringDoneStartsCelebration() {
        var animator = AvatarAnimator()
        let mounted = animator.step(.init(now: 100, state: .done))
        XCTAssertEqual(mounted.stateAge, 3.87, accuracy: 1e-12)
        XCTAssertFalse(mounted.moving)
        XCTAssertEqual(pose(mounted, time: 0).ribbons, 0)
        XCTAssertEqual(AvatarPose(.init(seed: seed, time: 0, state: .done)).ribbons, 0)

        animator.reset()
        _ = animator.step(.init(now: 100, state: .idle))
        let entered = animator.step(.init(now: 101, state: .done))
        XCTAssertEqual(entered.stateAge, 0)
        XCTAssertTrue(entered.moving)
        let turning = animator.step(.init(now: 102, state: .done))
        XCTAssertEqual(turning.stateAge, 1)
        XCTAssertEqual(pose(turning, time: 2).ribbons, 1)
        XCTAssertEqual(pose(turning, time: 2).cage, 1)
    }

    func testMoodOnlyChangesKeepBothSidesOfWorkingTurnOnTheSameClock() throws {
        var animator = AvatarAnimator()
        _ = animator.step(.init(now: 0, state: .working))
        let turnStart = 1.2 + 1.2 * AvatarNoise.value(seed, 41)
        let changeAt = turnStart + 0.2
        _ = animator.step(.init(now: changeAt, mood: .happy, state: .working))
        let frameAt = changeAt + 0.2
        let step = animator.step(.init(now: frameAt, mood: .happy, state: .working))
        XCTAssertEqual(step.stateAge, frameAt)
        let before = try XCTUnwrap(step.mood.blend).from
        XCTAssertEqual(before.state, .working)
        XCTAssertEqual(try XCTUnwrap(before.age), changeAt)
        let shown = pose(step, time: frameAt)
        let uninterrupted = AvatarPose(.init(seed: seed, time: frameAt, state: .working, stateAge: frameAt))
        XCTAssertGreaterThan(uninterrupted.ribbons, 0)
        XCTAssertEqual(shown.sweep, uninterrupted.sweep)
        XCTAssertEqual(shown.ribbons, uninterrupted.ribbons)
        XCTAssertEqual(shown.yaw, uninterrupted.yaw)
        XCTAssertGreaterThan(shown.eyes.arc, 0)
        XCTAssertLessThan(shown.eyes.arc, 1)
    }

    func testLeavingAStateFreezesItsAgeButItsAmbientMotionContinues() throws {
        var animator = AvatarAnimator()
        _ = animator.step(.init(now: 0, state: .working))
        let leaveAt = 1.2 + 1.2 * AvatarNoise.value(seed, 41) + 0.3
        _ = animator.step(.init(now: leaveAt, state: .waiting))
        let now = leaveAt + 0.2
        let step = animator.step(.init(now: now, state: .waiting))
        let blend = try XCTUnwrap(step.mood.blend)
        XCTAssertEqual(try XCTUnwrap(blend.from.age), leaveAt)
        XCTAssertEqual(step.stateAge, 0.2, accuracy: 1e-12)
        let before = AvatarPose(.init(seed: seed, time: now, state: .working, stateAge: leaveAt))
        let after = AvatarPose(.init(seed: seed, time: now, state: .waiting, stateAge: step.stateAge))
        XCTAssertEqual(pose(step, time: now), AvatarPose.blend(before, after, blend.t))
    }

    func testInterruptingATransitionContinuesFromExactlyTheShownPose() throws {
        var animator = AvatarAnimator()
        _ = animator.step(.init(now: 0, state: .working))
        _ = animator.step(.init(now: 2, state: .done))
        let before = animator.step(.init(now: 2.2, state: .done))
        let after = animator.step(.init(now: 2.2, state: .blocked))
        XCTAssertEqual(after.stateAge, 0)
        let blend = try XCTUnwrap(after.mood.blend)
        XCTAssertEqual(blend.t, 0)
        XCTAssertEqual(blend.from.state, .done)
        XCTAssertEqual(try XCTUnwrap(blend.from.age), 0.2, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(blend.from.blend).from.state, .working)
        XCTAssertEqual(pose(before, time: 2.2), pose(after, time: 2.2))
    }

    func testReducedMotionSnapsChangesWithoutRestartingMoodOnlyStateAge() {
        var animator = AvatarAnimator()
        _ = animator.step(.init(now: 10, state: .working))
        let snap = animator.step(.init(
            now: 12, mood: .happy, target: AvatarLook(x: 0.5, y: -0.25), reducedMotion: true, state: .working))
        XCTAssertEqual(snap.stateAge, 2)
        XCTAssertFalse(snap.moving)
        XCTAssertNil(snap.mood.blend)
        XCTAssertEqual(snap.gaze, AvatarGaze(x: 0.5, y: -0.25, weight: 1))
        let done = animator.step(.init(now: 13, reducedMotion: true, state: .done))
        XCTAssertEqual(done.stateAge, 0)
        XCTAssertNil(done.mood.blend)
        let still = pose(done, time: 13, reducedMotion: true)
        XCTAssertEqual(still.ribbons, 0)
        XCTAssertEqual(still.lift, 0)
        XCTAssertEqual(still.yaw, AvatarPose.baseYaw)
        XCTAssertEqual(still, pose(done, time: 99, reducedMotion: true))
    }

    func testEyesMorphWithoutAnArtificialBlinkAndRibbonsDoNotUnwindWhenFading() {
        var from = AvatarPose(), to = AvatarPose()
        from.eyes = AvatarEyeLook(arc: 0, slit: 1)
        from.ribbons = 1
        from.cage = 1
        from.sweep = 40
        to.eyes = AvatarEyeLook(arc: 1)
        to.bang = 1
        let shown = AvatarPose.blend(from, to, 0.25)
        XCTAssertEqual(shown.eyes, AvatarEyeLook(arc: 0.25, slit: 0.75))
        XCTAssertEqual(shown.blink, 0)
        XCTAssertEqual(shown.ribbons, 0.75)
        XCTAssertEqual(shown.cage, 1)
        XCTAssertEqual(shown.sweep, 40)
        XCTAssertEqual(shown.bang, 0.25)
    }

    func testFreezingDropsOldHistoryWithoutLosingStateOrAge() throws {
        var look = AvatarMoodState(state: .working, age: 0)
        for i in 1...12 {
            look = AvatarMoodState(state: .done, mood: .happy, age: Double(i), from: look, t: 0.5)
        }
        var frozen = look.frozen()
        XCTAssertEqual(frozen.state, .done)
        XCTAssertEqual(try XCTUnwrap(frozen.age), 12)
        var depth = 0
        while let blend = frozen.blend {
            depth += 1
            frozen = blend.from
        }
        XCTAssertEqual(depth, 3)
        XCTAssertEqual(try XCTUnwrap(frozen.age), 9)
        let almostFinished = AvatarMoodState(state: .blocked, age: 2, from: look, t: 0.99).frozen()
        XCTAssertNil(almostFinished.blend)
        XCTAssertEqual(almostFinished.state, .blocked)
        XCTAssertEqual(almostFinished.age, 2)
    }

    func testNoiseCoercesDoubleIndicesAfterSlotArithmeticLikeJavaScript() {
        XCTAssertEqual(AvatarNoise.value(seed, 4_294_967_297.0), AvatarNoise.value(seed, 1))
        XCTAssertEqual(AvatarNoise.value(seed, -4_294_967_297.0), AvatarNoise.value(seed, -1))
        XCTAssertEqual(AvatarNoise.value(seed, 3.9), AvatarNoise.value(seed, 3))
        XCTAssertEqual(AvatarNoise.value(seed, -0.9), AvatarNoise.value(seed, 0))
        XCTAssertEqual(AvatarNoise.value(seed, Double.infinity), AvatarNoise.value(seed, 0))
        // Sampled directly from 0.3.0's computePose: a large finite clock must not reset to zero
        // or trap when the noise slot exceeds Int's range.
        let future = AvatarPose(.init(seed: seed, time: 1e20))
        XCTAssertEqual(future.yaw, -0.3034487697372947, accuracy: 1e-12)
        XCTAssertEqual(future.scaleY, 1.0027744520557742, accuracy: 1e-12)
        XCTAssertEqual(future.gazeX, 0.47621728470548985, accuracy: 1e-12)
        XCTAssertEqual(future.gazeY, 0.2777934160782024, accuracy: 1e-12)
        let past = AvatarPose(.init(seed: seed, time: -1e20))
        XCTAssertEqual(past.yaw, -0.2965512302627053, accuracy: 1e-12)
        XCTAssertEqual(past.gazeX, 0)
        XCTAssertEqual(past.gazeY, 0)
    }

    func testOnlyExactPlainEyeLooksUseOriginalPrimitives() {
        XCTAssertEqual(plainLook(AvatarEyeLook()), .pill)
        XCTAssertEqual(plainLook(AvatarEyeLook(arc: 1)), .happy)
        XCTAssertNil(plainLook(AvatarEyeLook(arc: 0.001)))
        XCTAssertNil(plainLook(AvatarEyeLook(slit: 1)))
        let spot = EyeSpot(x: 40, y: 40, w: 4, h: 11, open: 8, shift: 0.54)
        let pill = eyeOutline(AvatarEyeLook(), spot)
        let arc = eyeOutline(AvatarEyeLook(arc: 1), spot)
        let slit = eyeOutline(AvatarEyeLook(slit: 1), spot)
        let mixed = eyeOutline(AvatarEyeLook(arc: 0.2, slit: 0.3), spot)
        XCTAssertEqual(mixed.count, 40)
        for i in mixed.indices {
            XCTAssertEqual(mixed[i].x, pill[i].x * 0.5 + arc[i].x * 0.2 + slit[i].x * 0.3, accuracy: 1e-12)
            XCTAssertEqual(mixed[i].y, pill[i].y * 0.5 + arc[i].y * 0.2 + slit[i].y * 0.3, accuracy: 1e-12)
        }
        let path = eyePath(AvatarEyeLook(arc: 0.2, slit: 0.3), spot)
        XCTAssertEqual(path.filter { $0 == "Q" }.count, 40)
        XCTAssertTrue(path.hasPrefix("M"))
        XCTAssertTrue(path.hasSuffix("Z"))
    }
}
