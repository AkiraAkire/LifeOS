# 技术架构规范

## 技术基线

- 平台：macOS 14 Sonoma 及以上。
- 语言：Swift 5.9 及以上。
- UI：SwiftUI。
- 数据：SwiftData。
- 架构：轻量 MVVM + Service。
- 优先使用 Apple 官方框架；V1 不添加第三方依赖。

## 分层职责

```text
SwiftUI Views → ViewModels / Feature State → Services → SwiftData Models
```

- `Models`：持久化实体、关系和轻量领域枚举；不承载界面状态。
- `Views`：渲染界面、接收用户输入、调用 ViewModel 或 Service。
- `ViewModels`：页面筛选、排序、聚合状态与用户操作编排。
- `Services`：跨模块业务规则，例如课次生成、Today 聚合、日历聚合和任务完成同步。
- `Utilities`：日期、颜色、常量和预览数据等无业务副作用的工具。

## 数据与扩展原则

- 持久化日期使用 `Date`，不得保存格式化日期字符串。
- 每周课程只保存规则；按日期生成展示实例，避免提前复制大量日历事件。
- 日历与 Today 使用非持久化 `ScheduleItem` 聚合对象展示不同来源的数据。
- 枚举优先保存稳定的 String raw value，避免未来迁移风险。
- 未来 iCloud / AI 只能通过 Service 层接入，不得让 View 直接依赖网络或模型提供方。

## 推荐目录

```text
LifeOS/
├── App/
├── Models/
├── Views/{Root,Today,Calendar,Tasks,Courses,Journal,Settings,Shared}/
├── ViewModels/
├── Services/
├── Utilities/
├── Resources/
└── Tests/
```

## 依赖约束

- View 不直接复制或转换其他模块的实体。
- 仅 Service 可以处理跨实体同步，例如 Assignment 与 Task 的关联。
- 避免单例泛滥；依赖优先通过 SwiftUI Environment 或初始化注入。
- 在模型字段或关系发生破坏性调整前，先记录到 `07-decision-log.md` 并评估 SwiftData 迁移。
