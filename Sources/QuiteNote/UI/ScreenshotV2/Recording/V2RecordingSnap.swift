import Foundation

/// 时间线把手的统一吸附计算。
///
/// 吸附只关心“当前候选位置”和“合法范围”，因此左右把手使用完全相同的规则，
/// 不会因为拖动方向不同而出现一边吸附、一边只是被硬钳制的情况。
enum V2RecordingSnap {
    // 只在非常接近切点时吸附，避免拖动把手时出现明显“黏住/阻尼大”的感觉。
    // 0.18 秒约等于 30fps 时间线上的 5 帧，仍能容错手指/鼠标微小抖动。
    static let threshold: Double = 0.18

    static func target(proposed: Double,
                       lowerBound: Double,
                       upperBound: Double,
                       candidates: [Double],
                       threshold: Double = Self.threshold) -> Double? {
        let lower = min(lowerBound, upperBound)
        let upper = max(lowerBound, upperBound)
        let valid = candidates.filter { $0 >= lower && $0 <= upper }
        guard let nearest = valid.min(by: { abs($0 - proposed) < abs($1 - proposed) }) else {
            return nil
        }
        return abs(nearest - proposed) <= threshold ? nearest : nil
    }
}
