# 当前技术架构

> 更新至 2026-09-02。架构以可运行、可备份的本地 macOS 应用为基线；以下内容描述当前代码职责，以及下一阶段不可突破的扩展边界。

## 技术基线

- 平台：macOS 14 Sonoma 及以上。
- 语言：Swift 5.9 及以上。
- UI：SwiftUI + AppKit 文件面板／Dock 图标桥接。
- 数据：SwiftData。
- 依赖：仅 Apple 官方框架，无第三方运行时依赖。
- 存储：SwiftData 持久化实体 + UserDefaults 本机展示偏好 + 应用私有目录自动备份。

## 当前目录与职责

```text
lifeOS/                  # 项目根目录
├── LifeOS/
│   ├── App/             # 应用入口、导航协调、SwiftData 容器、生命周期自动保护
│   ├── DesignSystem/    # 语义颜色、字号、间距与圆角令牌
│   ├── Models/          # SwiftData 实体、日期／课表偏好与领域枚举
│   ├── Services/        # 聚合、人工测试数据、备份和恢复规则
│   ├── Views/
│   │   ├── Root/        # NavigationSplitView 与 Sidebar
│   │   ├── Features/    # 当前功能视图与局部编辑状态
│   │   ├── Shared/      # 页面头部、表面、空状态等共享组件
│   │   └── Today/       # Today 相关视图
│   └── Resources/       # 资产、Entitlements、人工测试数据
├── LifeOSTests/         # CoreModelTests 单元测试
├── docs/                # 项目标准与决策记录
├── development-logs/    # 按日开发记录
└── scripts/             # 日志等维护脚本
```

目前多个功能视图集中在 `Views/Features/FeatureViews.swift` 中。它是已验证的实现边界，不应因小功能进行大规模拆分；当某一模块需要独立演进时，可按模块将其视图和局部状态迁出，并保持 Service API 不变。

## 分层与数据流

```text
SwiftUI View / 本地 @State
        ↓
Service（日期规则、聚合、备份、导入）
        ↓
SwiftData ModelContext + UserDefaults 偏好
        ↓
本机 SwiftData 存储 / 应用私有自动备份
```

- `Models`：持久化实体、关系与轻量领域规则；不保存页面临时选择状态。
- `Views`：渲染、输入、Sheet／确认对话框和本地 UI 状态；不可复制跨模块数据。
- `Services`：唯一的跨模块规则入口。`ScheduleAggregationService` 聚合 Today／日历，`DailyLifeOverviewService` 聚合 Calendar／Journal，`HabitHistoryService` 计算轨迹，`LifeOSBackupService` 负责归档与恢复。
- `AppNavigationCoordinator`：只保存一次性的跨页面日期路由请求，不持久化用户内容。
- ViewModel：当前未单独建立目录；页面筛选与短生命周期状态留在对应 View。新增复杂、可复用的编排逻辑时才新增轻量 ViewModel，避免为了形式而搬运状态。

## 数据所有权

| 数据 | 唯一来源 | 读取方 |
| --- | --- | --- |
| 课程重复规则 | `CourseSession` | 课表、Today、Calendar、每日生活摘要 |
| 个人日程 | `Event` | Today、Calendar、Journal 足迹 |
| 任务与完成状态 | `Task` | Tasks、Today、Calendar／Journal 每日摘要 |
| 每日日记与天气 | `JournalEntry` | Journal、Sidebar、Calendar 当天生活 |
| 习惯完成状态 | `HabitRecord` | Calendar、Journal、完成轨迹 |
| 学期范围与课表节次 | `SemesterDateRangeStore`、`TimetablePeriodStore` | Today、课表、课程编辑 |
| 日历／日记展示习惯 | `HabitDisplayConfiguration` | Calendar、Journal |

`ScheduleItem`、`TodayOverview`、`DailyLifeOverview` 与 `DailyHabitStatus` 都是即时展示对象，禁止持久化为重复的“每日汇总”表。

## 日期、课表与教学周

- 所有持久化日期使用 `Date`；自然日比较统一使用 `Calendar.startOfDay(for:)` 与下一日边界。
- `CourseSession` 保存星期、起止分钟、有效日期和单双周规则；不预先复制为多条日程。
- 学期开始日期所在的自然周为第 1 周，之后每周星期一进入下一周。
- 全局学期范围与课程独立覆盖都通过 `SemesterDateRange` 解释；课程覆盖不影响其他课程。
- `TimetablePeriod` 只决定课表网格如何映射／显示真实课程时间，不改写 `CourseSession` 的事实数据。

## 数据保护架构

- `LifeOSBackupService` 写入版本化、带关系 UUID 的 JSON `.lifeosbackup`，不直接复制 SwiftData 私有数据库文件。
- 外部导出／导入经 `NSSavePanel`／`NSOpenPanel` 完成；App Sandbox 仅启用用户明确选择文件的读写权限。
- `RootView` 在启动与进入非活动／后台状态时更新当日自动快照；同日快照原地覆盖，避免无界增长。
- 恢复和人工测试数据导入前创建恢复点；恢复先校验格式、唯一标识、关联完整性和课表时间合法性，再替换本机数据。

## 扩展约束

- 未来 iCloud、同步或 AI 只能经新增 Service 接入，View 不可直接依赖网络或模型提供方。
- “今日节奏”“课程成长档案”“一天生活回放”和“每周收束”必须优先从现有实体动态聚合；除非性能测量证明必要，禁止创建按日／按周的重复汇总实体。
- 未来助手的输入必须由显式的本地上下文构建器生成，输出需要携带可展示的事实依据；网络调用、模型密钥和授权状态不得散落在 View 中。
- 数据 Schema 的破坏性调整、备份格式版本变更和关系语义变化必须先记录到 `07-decision-log.md` 并新增迁移／恢复测试。
- 不引入第三方依赖，除非用户明确批准并记录其维护、隐私和离线影响。
