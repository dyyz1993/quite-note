import SwiftUI
import Combine

/// 热力图视图模型：统计记录数量并提供筛选
final class HeatmapViewModel: ObservableObject {
    @Published var buckets: [Date: Int] = [:]
    @Published var filterDate: Date? = nil
    private let store: RecordStore
    private var cancellables = Set<AnyCancellable>()

    /// 通过记录更新每日计数
    init(store: RecordStore) {
        self.store = store
        recompute()
        
        // Subscribe to store changes
        store.$records
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Last 12 days to match design height
        let cells = (0..<12).map { i in calendar.date(byAdding: .day, value: -i, to: today)! }
        
        VStack(alignment: .center, spacing: 6) {
            VStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20))
                    .foregroundColor(.themeGray500)
                Text("WEEK")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.themeGreen.opacity(0.5))
            }
            .padding(.bottom, 24) // More padding to separate header from cells
            
            VStack(spacing: 6) { // gap-1.5 (6px)
                ForEach(cells, id: \.self) { d in
                    let count = vm.buckets[d] ?? 0
                    
                    cellView(date: d, count: count)
                        .onTapGesture {
                            // Toggle filter
                            if vm.filterDate == d {
                                vm.filterDate = nil
                            } else {
                                vm.filterDate = d
                            }
                        }
                        .onHover { h in hoverDay = h ? d : nil }
                        .overlay(alignment: .leading) {
                            if hoverDay == d {
                                Text("\(calendar.isDateInToday(d) ? "今日" : d.formatted(date: .abbreviated, time: .omitted))：\(count) 条")
                                    .font(.system(size: 10))
                                    .padding(4)
                                    .background(Color.gray.opacity(0.9))
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .offset(x: 24) // Adjusted offset
                                    .fixedSize()
                                    .transition(.opacity)
                                    .zIndex(100)
                            }
                        }
                }
            }
        }
        .padding(.vertical, 24) // py-6
        .frame(width: 64)
    }

    private func cellView(date: Date, count: Int) -> some View {
        let color: Color
        let shadowColor: Color
        let shadowRadius: CGFloat
        let isSelected = vm.filterDate == date
        
        // Exact Tailwind color mapping from note.jsx
        if count == 0 {
            // bg-gray-700/50 -> themeGray700 is gray-700
            color = Color.themeGray700.opacity(0.5)
            shadowColor = .clear
            shadowRadius = 0
        } else if count < 3 {
            // bg-green-900/60
            color = Color.themeGreen900.opacity(0.6)
            shadowColor = .clear
            shadowRadius = 0
        } else if count < 8 {
            // bg-green-600/80
            color = Color.themeGreen600.opacity(0.8)
            shadowColor = .clear
            shadowRadius = 0
        } else {
            // bg-green-400
            color = Color.themeGreen
            // shadow-[0_0_8px_rgba(74,222,128,0.6)]
            shadowColor = Color.themeGreen.opacity(0.6)
            shadowRadius = 4 // 8px blur / 2
        }
        
        return RoundedRectangle(cornerRadius: 2) // rounded-sm (2px)
            .fill(color)
            .frame(width: 12, height: 12)
            .shadow(color: shadowColor, radius: shadowRadius)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white, lineWidth: isSelected ? 1.5 : 0)
            )
            .scaleEffect(hoverDay == date ? 1.1 : 1.0) // hover:scale-110
            .animation(.spring(response: 0.3), value: hoverDay == date)
    }
}
