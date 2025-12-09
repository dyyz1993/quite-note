import SwiftUI
import Combine

/// Array 扩展，用于将数组分割成指定大小的子数组
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

/// 热力图视图模型：统计记录数量并提供筛选
final class HeatmapViewModel: ObservableObject {
    @Published var buckets: [Date: Int] = [:]
    @Published var filterDate: Date? = nil
    private let store: RecordStore
    private var cancellables = Set<AnyCancellable>()
    private var recomputeWorkItem: DispatchWorkItem?

    /// 通过记录更新每日计数
    init(store: RecordStore) {
        self.store = store
        recompute()
        
        // Subscribe to store changes，使用防抖机制减少频繁计算
        store.$records
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in 
                self?.debouncedRecompute()
            }
            .store(in: &cancellables)
    }
    
    /// 析构函数，确保清理资源
    deinit {
        cancellables.removeAll()
        recomputeWorkItem?.cancel()
        recomputeWorkItem = nil
    }
    
    /// 防抖重新计算，减少频繁更新
    private func debouncedRecompute() {
        // 取消之前的计算任务
        recomputeWorkItem?.cancel()
        
        // 创建新的计算任务
        let workItem = DispatchWorkItem { [weak self] in
            self?.recompute()
        }
        recomputeWorkItem = workItem
        
        // 延迟执行计算
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    /// 重新聚合每日数量
    func recompute() {
        var map: [Date: Int] = [:]
        for r in store.records {
            let day = Calendar.current.startOfDay(for: r.createdAt)
            map[day] = (map[day] ?? 0) + 1
        }
        buckets = map
    }

    /// 根据筛选日期返回记录列表（缺省返回全部）
    func filteredRecords() -> [Record] {
        guard let day = filterDate else { return store.records }
        return store.records.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }
    }
}

/// 热力图视图：简单方格按深浅显示数量
struct HeatmapView: View {
    @ObservedObject var vm: HeatmapViewModel
    @State private var hoverDay: Date? = nil

    /// 构建热力图方格
    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            headerView
                .padding(.bottom, 24)
            
            cellsView
        }
        .padding(.top, 12) // Reduced top padding to move icon up
        .padding(.bottom, 24)
        .frame(width: 64)
    }
    
    private var headerView: some View {
        VStack(spacing: 4) {
            LucideView(name: .activity, size: 22, color: .white)
                .shadow(color: .white.opacity(0.5), radius: 4, x: 0, y: 0)
            Text("WEEK")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.white.opacity(0.5))
        }
    }
    
    private var cellsView: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Last 21 days to match design height (7 rows x 3 columns)
        let cells = (0..<21).map { i in calendar.date(byAdding: .day, value: -i, to: today)! }
        
        // 将日期分组为每行3个
        let rows = cells.chunked(into: 3)
        
        return VStack(spacing: 4) { // 减小间距以适应更多列
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) { // 减小间距以适应更多列
                    ForEach(row, id: \.self) { d in
                        let count = vm.buckets[d] ?? 0
                        
                        cellView(date: d, count: count)
                            .onTapGesture {
                                if vm.filterDate == d {
                                    vm.filterDate = nil
                                } else {
                                    vm.filterDate = d
                                }
                            }
                            .onHover { h in hoverDay = h ? d : nil }
                            .pointingHandCursor()
                            .overlay(alignment: .leading) {
                                if hoverDay == d {
                                    tooltipView(date: d, count: count)
                                }
                            }
                    }
                }
            }
        }
    }
    
    private func tooltipView(date: Date, count: Int) -> some View {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE" // 星期几的完整格式
        let weekday = formatter.string(from: date)
        
        let dateText = calendar.isDateInToday(date) ? "今日" : date.formatted(date: .abbreviated, time: .omitted)
        
        return Text("\(dateText) (\(weekday))：\(count) 条")
            .font(.system(size: 10))
            .padding(4)
            .background(Color.themeGray700) // bg-gray-700
            .foregroundColor(.themeGray200) // text-gray-200
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .offset(x: 24) // Adjusted offset
            .fixedSize()
            .transition(.opacity)
            .zIndex(100)
    }

    private func cellView(date: Date, count: Int) -> some View {
        let color: Color
        let shadowColor: Color
        let shadowRadius: CGFloat
        let isSelected = vm.filterDate == date
        
        // Exact Tailwind color mapping from note.jsx
        if count == 0 {
            color = Color.themeGray700
            shadowColor = .clear
            shadowRadius = 0
        } else if count < 3 {
            color = Color.themeGreen900
            shadowColor = .clear
            shadowRadius = 0
        } else if count < 8 {
            color = Color.themeGreen600
            shadowColor = .clear
            shadowRadius = 0
        } else {
            color = Color.themeGreen500
            shadowColor = Color.themeGreen500.opacity(0.6)
            shadowRadius = 4
        }
        
        return RoundedRectangle(cornerRadius: 1) // 调整圆角以适应更小的方块
            .fill(color)
            .frame(width: 6, height: 6) // 调整方块大小以适应3列布局
            .shadow(color: shadowColor, radius: shadowRadius)
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .stroke(Color.white.opacity(0.4), lineWidth: isSelected ? 1 : 0)
            )
            .scaleEffect(hoverDay == date ? 1.2 : 1.0) // 增加悬停缩放效果以补偿更小的尺寸
            .animation(.spring(response: 0.3), value: hoverDay == date)
    }
}
