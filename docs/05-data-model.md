# SwiftData 数据模型与本机偏好

> 更新至 2026-08-30。SwiftData 负责用户生活数据；展示偏好与自动备份元数据不以额外业务实体重复保存。

## 当前持久化实体

| 实体 | 核心字段 | 关键关系／语义 |
| --- | --- | --- |
| `AppConfiguration` | `id`、`createdAt` | SwiftData 容器的应用级锚点；当前通用偏好仍由 UserDefaults 保存 |
| `Task` | 标题、描述、计划日期、具体起止时间、截止日期、优先级、状态、完成时间、排序值 | 可关联 Course、Project、Assignment 与 Tag；Today 拖放使用 `plannedDate` |
| `Event` | 标题、描述、起止时间、全天、类型、地点 | 可关联 Course 与 Tag；是个人日程的唯一来源 |
| `Course` | 名称、教师、教室、显示色、学期、备注、独立日期覆盖 | 拥有 CourseSession、Assignment、Exam；关联 Task 与 Event |
| `CourseSession` | 星期、起止分钟、生效日期、结束日期、单双周、教室覆盖、启用状态 | 课程的重复规则；按日期动态生成展示实例 |
| `Assignment` | 标题、描述、布置日期、截止日期、完成状态 | 属于 Course；可关联一个可执行 Task |
| `Exam` | 标题、描述、起止时间、地点 | 属于 Course；动态进入日历与 Today |
| `JournalEntry` | 日期、心情、天气、每日一句、正文、重要事件、更新时间 | 一个自然日只应有一条；由 `JournalEntryService` 维护 |
| `Habit` | 名称、SF Symbol、创建时间 | 级联拥有 HabitRecord；目前通过 Calendar／Journal 使用 |
| `HabitRecord` | 打卡日期 | 属于 Habit；同日历史重复记录在轨迹统计中只计一次 |
| `Project` | 名称、描述、截止日期、归档状态 | 与 Task 关联；暂不提供主导航 UI，但会被备份与测试数据保留 |
| `Tag` | 名称、颜色、创建时间 | 多对多关联 Task 与 Event |

## 非实体偏好与展示对象

| 类型 | 存放位置 | 作用 |
| --- | --- | --- |
| `TimetablePeriod` | UserDefaults | 课表节次名称与起止分钟；只影响网格映射 |
| `SemesterDateRange` | UserDefaults | 全局学期起止日期；周数由日期范围计算 |
| 展示习惯 UUID 集合 | UserDefaults | 控制 Calendar／Journal 显示哪些 Habit，不修改打卡历史 |
| 外观、启动页、周起始日、24 小时制 | UserDefaults / `@AppStorage` | 通用界面偏好 |
| `ScheduleItem`、`TodayOverview`、`DailyLifeOverview`、`DailyHabitStatus` | 内存动态计算 | 只用于聚合展示，绝不持久化为重复汇总 |

## 关系与删除规则

- 删除 Course：级联删除 CourseSession、Assignment、Exam；关联 Task 与 Event 保留，但 `course` 解除关联。
- 删除 CourseSession：只删除该条重复规则，不影响 Course、同课程其他课次、作业或考试。
- 删除 Project：关联 Task 保留，`project` 置空。
- 删除 Habit：级联删除 HabitRecord。
- 删除 Task：关联 Assignment 保留，`linkedTask` 置空。
- 删除 JournalEntry：仅删除指定自然日的日记，不影响当天课程、日程、任务或 HabitRecord。
- Assignment 的可执行状态通过关联 Task 表示；跨实体同步必须经 Service 或明确的编辑路径完成。

## 日期与教学周规则

- 所有日期持久化为 `Date`；页面显示时才本地化格式。
- 某一天统一使用当前 `Calendar` 的 `startOfDay(for:)` 比较。
- `CourseSession.startTimeMinutes` 与 `endTimeMinutes` 是当天 00:00 起的分钟数，且结束必须晚于开始。
- 课程时间按周一至周日排列；同一天按开始、结束时间和稳定 UUID 顺序排列。
- 课程日期默认继承全局 `SemesterDateRange`。课程关闭“跟随课表学期日期”后保存独立起止日期，并更新该课程全部 CourseSession；之后全局范围变更不会覆盖该课程。
- 开始日期所在的星期一至星期日是第 1 周，之后每周星期一换周。单双周以 CourseSession 的有效日期所在第 1 周为基准。

## 完整备份与恢复

- `.lifeosbackup` 是版本化 JSON 档案，使用稳定 UUID 重建实体与关系；禁止将 SwiftData 私有数据库文件当作备份格式。
- 档案包含全部 SwiftData 实体、关系标识、课表节次、学期范围、展示习惯和通用偏好。
- 读取档案前校验版本、唯一标识、关系引用、节次重叠与课程起止时间；校验失败不得写入本机数据。
- 自动保护仅保存于应用私有目录：最近 7 天日快照、较早 4 周周快照、最多 14 个导入前／恢复前保护点。
- 恢复会替换当前本机实体和偏好；恢复前必须先创建恢复点，用户界面必须显示破坏性确认。
