import XCTest
import CoreMedia
@testable import QuiteNote

/// 暂停/恢复时间轴纯函数测试（PTS 前移法）
final class RecordingTimingTests: XCTestCase {

    private func t(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    func testEffectivePTSShiftsBackByPausedDuration() {
        // 暂停了 10 秒后，原始 100s 的帧应落在成片 90s 处
        let effective = V2RecordingTiming.effectivePTS(
            rawPTS: t(100), pausedDuration: t(10))
        XCTAssertEqual(effective.seconds, 90, accuracy: 0.001)
    }

    func testAccumulatedPauseAddsGap() {
        // 已累计 3s 暂停，又从 50s 暂停到 57s → 累计 10s
        let acc = V2RecordingTiming.accumulatedPause(
            previous: t(3), pauseStartedAt: t(50), resumedAt: t(57))
        XCTAssertEqual(acc.seconds, 10, accuracy: 0.001)
    }

    func testAccumulatedPauseIgnoresInvalidClock() {
        // 恢复时刻早于暂停开始（时钟异常）时不累计，防御性返回旧值
        let acc = V2RecordingTiming.accumulatedPause(
            previous: t(3), pauseStartedAt: t(50), resumedAt: t(40))
        XCTAssertEqual(acc.seconds, 3, accuracy: 0.001)
    }

    func testTimelineIsContinuousAcrossPause() {
        // 端到端语义验证：暂停前最后一帧 40s；暂停 40→70s；恢复后首帧原始 70.2s
        // → 有效 PTS = 70.2 − 30 = 40.2s，与 40s 无缝衔接
        let paused = V2RecordingTiming.accumulatedPause(
            previous: .zero, pauseStartedAt: t(40), resumedAt: t(70))
        let resumed = V2RecordingTiming.effectivePTS(rawPTS: t(70.2), pausedDuration: paused)
        XCTAssertEqual(resumed.seconds, 40.2, accuracy: 0.001)
        XCTAssertGreaterThan(resumed.seconds, 40, "恢复后首帧必须在暂停前末帧之后（PTS 单调）")
    }

    func testPadPTSExcludesPausedHoles() {
        // 录制 100s（其中暂停 20s）→ 补尾帧应在成片 80s 处
        let pad = V2RecordingTiming.padPTS(now: t(100), pausedDuration: t(20))
        XCTAssertEqual(pad.seconds, 80, accuracy: 0.001)
    }
}
