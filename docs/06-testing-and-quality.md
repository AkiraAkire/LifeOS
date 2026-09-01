# 测试与质量规范

## 交付门槛

每次代码或行为变更交付前必须满足：

1. 修改或新增领域规则时，新增／更新 `LifeOSTests/CoreModelTests.swift` 的单元测试。
2. 受影响的 macOS target 成功构建；完整回归优先执行全部测试。
3. 手工检查浅色、深色、空数据、人工测试数据和常用窗口尺寸。
4. 不破坏 Today、任务、课程、课表、日历、日记和数据保护的共享数据语义。
5. 在当天开发日志记录验证结果、已知限制和后续待办。
6. 创建一个只包含本次源代码、测试、文档和日志的聚焦 Git commit。

仅修改文档或工作流时可不执行应用测试，但必须记录“未运行测试的原因”，并执行 Markdown／引用与 `git diff --check` 验证。

## 当前自动化覆盖

`CoreModelTests` 当前覆盖以下规则：

- Task 完成／恢复状态、任务分组，以及通过拖放或任务页设置 Today 时保留截止日期、清除旧具体安排时间的规则。
- Course、Tag、Project、Assignment 与 Task 的关系和完成进度，以及课程预设／文字／图片图标与完整备份恢复。
- CourseSession 的单双周、生效日期、周一优先排序、课次编辑／删除。
- `SemesterDateRange` 的自然周、星期一换周、总周数和课程独立日期覆盖。
- `TimetablePeriod` 合法性与 `TimetableLayout` 跨节映射、冲突并列轨道。
- `ScheduleAggregationService` 的课程、日程、考试、带时间任务聚合与时间排序。
- JournalEntry 同一自然日复用、天气更新不覆盖正文、指定日记删除。
- 日记迷你月历的连续六周日期范围与用户配置的每周起始日。
- DailyLifeOverview 的日记、HabitRecord、任务与日程联动。
- 月日历六行日期布局及其星期起始顺序，供主月历和迷你月历导航共同使用。
- Habit 展示偏好、同日记录归一化、月／年完成次数、当前连续和最长连续。
- 人工测试数据清空／导入。
- 完整备份的关系和偏好往返、损坏关联拒绝恢复、自动日快照与恢复点保留。

截至 2026-09-01，完整 macOS 测试套件为 **34 项、0 失败**。

## 建议命令

```zsh
xcodebuild -project LifeOS.xcodeproj -scheme LifeOS \
  -destination 'platform=macOS' test

xcodebuild -project LifeOS.xcodeproj -scheme LifeOS \
  -destination 'platform=macOS' build
```

若构建环境需要隔离 DerivedData，可加 `-derivedDataPath /private/tmp/lifeos-derived`。测试环境偶发的 `linkd.autoShortcut` 系统服务日志不等于测试失败；以 `** TEST SUCCEEDED **` 和 XCTest 失败数为准。

## 手工回归清单

- 创建课程、课程时间、作业、考试和个人日程，确认它们在 Today、Calendar 与 Journal 足迹中一致。
- 调整全局学期、课程独立日期和单双周，确认 Today 周次、课表筛选与课程显示一致。
- 在课表检查全部、单周、双周；确认跨节课程完整显示，冲突课程并列且双指缩放可用。
- 新建仅截止日期任务，将任务拖到 Today，完成后确认任务页、Calendar／Journal 摘要同步。
- 在 Calendar 创建日程，检查月格不出现任务标题溢出，点击任意日期格空白区域均可选择日期。
- 在月视图使用迷你月历前后切换并选择相邻月日期，确认主月历标题、选中日期与当天生活检查器同步；在 900pt 最小窗口确认辅助导航收起且主月历不横向溢出。
- 在 Calendar／Journal 管理展示习惯、打卡、打开完成轨迹，并确认月历、日记、Today 同步；未来日期不可补记。
- 创建／编辑／删除日记，确认天气快捷入口不会覆盖现有正文或心情。
- 执行“导出完整备份 → 恢复确认 → 恢复前保护点回退”演练；导入人工测试数据前确认已有自动保护。
- 检查中文文案、键盘可达性、浅色／深色外观，以及 900pt 最小窗口和常规宽窗口的布局。

## 失败处理

- 不忽略与并发、SwiftData 关系、备份恢复、数据丢失相关的警告或失败。
- 构建／测试失败时先修复或回退当前小改动，不叠加新功能。
- 对未能自动验证的 UI、系统权限或真实数据场景，在当天开发日志中记录环境、影响与下一步。
