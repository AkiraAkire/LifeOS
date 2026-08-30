# SwiftData 数据模型规范

## V1 实体

| 实体 | 核心字段 | 关系 |
| --- | --- | --- |
| `Task` | title、description、createdAt、plannedDate、startDate、endDate、deadline、priority、status、completedAt | Course?、Project?、Assignment?、Tag[] |
| `Event` | title、description、startDate、endDate、isAllDay、type、location | Course?、Tag[] |
| `Course` | name、instructor、classroom、colorHex、semester、note、startDateOverride、endDateOverride | CourseSession[]、Assignment[]、Exam[]、Task[] |
| `CourseSession` | weekday、startTimeMinutes、endTimeMinutes、startDate、endDate、weekPattern、recurrenceEnabled | Course |
| `Assignment` | title、description、assignedDate、dueDate、isCompleted | Course、linkedTask? |
| `Exam` | title、description、startDate、endDate、location | Course |
| `JournalEntry` | date、mood、weather、quote、content、importantEvents | 按自然日唯一 |
| `Tag` | name、colorHex、createdAt | Task[]、Event[] |

`TimetablePeriod` 是本机课表展示偏好，保存节次名称与开始 / 结束分钟数；它不属于 SwiftData 业务实体。`SemesterDateRange` 同样属于本机偏好，保存全局学期开始与结束日期；总周数由日期范围推导，不额外保存重复字段。`CourseSession` 继续保存课程的真实时间，避免调整课表展示规则时改写用户课程数据。

完整备份使用版本化 `.lifeosbackup` JSON 档案，而不是复制 SwiftData 私有数据库文件。档案保存全部 SwiftData 实体、实体关系标识，以及课表节次、学期范围、展示习惯和通用界面偏好；恢复时按标识重建关系并保留原有 UUID。应用会在私有 Application Support 目录维护自动保护档案：当天快照在启动和退出前更新为同一份，保留最近 7 天与更早 4 个自然周各一份；恢复和人工测试数据导入前各创建独立保护点，保留最近 14 份。自动保护不新增 SwiftData 实体，也不扫描用户的外部目录。

`Course.startDateOverride` 与 `Course.endDateOverride` 同时为空时，课程继承全局 `SemesterDateRange`；任一课程设置独立日期后，该课程的全部 `CourseSession` 使用覆盖范围。修改全局学期日期只更新继续继承全局范围的课程，不覆盖其他课程的独立设置。

`DailyLifeOverview` 与 `DailyHabitStatus` 是由 `JournalEntry`、`HabitRecord`、Task 和日程实体按自然日动态计算的展示对象，不属于 SwiftData 实体，也不得持久化为重复的每日汇总数据。

单项 Habit 的完成轨迹同样由该 Habit 的 `HabitRecord` 按本地自然日即时计算；同一天的重复旧记录在展示与统计中只计一次。月历支持对当天及过去日期补记或撤销，操作只新增或删除对应的 `HabitRecord`，不额外保存轨迹、连续天数或热力图数据。

日历与日记中的“展示习惯”选择保存为本机 `UserDefaults` 偏好，值为 Habit UUID 列表；它只控制页面呈现，不改变 `Habit`、`HabitRecord` 或任何历史完成记录。未设置偏好时默认展示全部 Habit。

## 为 V2 / V3 预留的实体

`Project`、`Habit`、`HabitRecord`、`InboxItem`、`DailySummary` 的完整字段在产品架构设计中已定义。若尚未被 V1 界面使用，可在阶段 1 创建模型，或在 V2 前以兼容迁移方式加入；选择须记录到决策日志。

## 关系与删除规则

- Course 删除：级联删除 CourseSession、Assignment、Exam；关联 Task 的 course 置空并保留 Task。
- Project 删除：Task 保留，project 置空。
- Habit 删除：级联删除 HabitRecord。
- Task 删除：关联 Assignment 保留，`linkedTask` 置空。
- CourseSession 是规则，不是预先生成的每次上课 Event。
- Assignment 默认创建关联的 Task；完成状态必须通过 Service 统一同步。

## 日期规则

- 数据层所有时间存为 `Date`。
- “某一天”的查询使用用户当前 Calendar 的 `startOfDay(for:)` 与下一日边界。
- CourseSession 的 `startTimeMinutes` / `endTimeMinutes` 表示从当天 00:00 起的分钟数。
- CourseSession 的 `weekPattern` 为每周、单周或双周；开始日期所在自然周（星期一至星期日）视为第 1 周，之后每周星期一进入下一周。设置独立日期的课程同样以其开始日期所在自然周作为第 1 周。
- 日期、时间与时区格式仅在 View 层本地化显示。
