import Foundation
import CoreMedia

/// 暂停/恢复的时间轴纯函数（PTS 前移法）
///
/// SCK 没有原生暂停。方案：暂停期间丢弃所有帧；恢复时把「暂停时长」累加进
/// pausedDuration，后续所有帧的有效 PTS = 原始 PTS − pausedDuration（整体前移），
/// 成片时间轴在暂停点无缝衔接。所有输入/输出都是 host clock 域的 CMTime。
enum V2RecordingTiming {

    /// 帧的有效 PTS（去掉暂停空洞后）
    static func effectivePTS(rawPTS: CMTime, pausedDuration: CMTime) -> CMTime {
        CMTimeSubtract(rawPTS, pausedDuration)
    }

    /// 恢复时刻结算：新的累计暂停时长 = 旧累计 + (恢复时刻 − 暂停开始时刻)
    static func accumulatedPause(previous: CMTime, pauseStartedAt: CMTime, resumedAt: CMTime) -> CMTime {
        guard pauseStartedAt.isValid, resumedAt.isValid, resumedAt > pauseStartedAt else {
            return previous
        }
        return CMTimeAdd(previous, CMTimeSubtract(resumedAt, pauseStartedAt))
    }

    /// 停止收尾时的补尾帧 PTS（当前时刻也要扣掉暂停空洞）
    static func padPTS(now: CMTime, pausedDuration: CMTime) -> CMTime {
        CMTimeSubtract(now, pausedDuration)
    }
}
