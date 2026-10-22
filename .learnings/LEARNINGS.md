
## 2026-10-23 · 主题体系"有而不用"是样乱之源（截图工具栏审计实锤）
- Category: best_practice | Area: frontend | Status: resolved
- Context: 用户质疑"颜色这里弄一点那里弄一点"→ 审计证实：项目 Theme 体系完整（Color/Spacing/Radius/Font/Animation 五件套），但截图工具栏 5 文件基本绕过——"选中蓝"4 种写法（Color.blue.opacity(0.8)/themeBlue500/themeBlue600.opacity(0.85)/裸 .blue）、容器底 3 种、white/black opacity 字面量 20 档；V2FloatingToolbar/V2SizeDragControl 的 theme 引用数为 0。根因有二：① Theme 缺"悬浮 overlay 工具条"语义 token（玻璃底/overlay 选中色），各文件只能现场发明；② 交互态 token（themeSelected/themeHover*）定义了但零使用，无任何约束
- Fix: Color+Theme 新增 themeOverlay* 语义组（GlassOuter/GlassInner 双层玻璃底、Selected 统一选中蓝、IconMuted、Divider），工具栏 5 文件全部 token 化（da06a1d）；圆角收敛到 ThemeRadius 档位（发明值 r10 弃用）
- 规则: 悬浮在截图/录屏内容上的工具条 UI 一律用 themeOverlay* token，禁止再写 Color.blue / Color.black.opacity / Color.white.opacity 字面量；新语义先查 Theme 有没有 token，缺就补 token 而不是现场发明
- 关联: 35a1816（二级栏视觉统一的前置修复）→ da06a1d（token 化根治）
