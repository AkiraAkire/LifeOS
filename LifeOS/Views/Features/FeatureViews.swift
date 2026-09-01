import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Today

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Event.startDate) private var events: [Event]
    @Query(sort: \Task.createdAt, order: .reverse) private var tasks: [Task]
    @Query(sort: \Exam.startDate) private var exams: [Exam]
    @State private var isReceivingTodayTask = false

    private let today = Date.now

    var body: some View {
        let timeline = ScheduleAggregationService.items(for: today, courses: courses, events: events, tasks: tasks, exams: exams)
        let semesterRange = SemesterDateRangeStore.load()
        let todayTasks = tasks.filter { TaskListGrouping.isScheduled($0, on: today) && $0.status != .completed }
        let taskList = tasks
            .filter { $0.status != .completed && !TaskListGrouping.isScheduled($0, on: today) }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }

        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                LifePageHeader(
                    eyebrow: greeting,
                    title: today.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide).day().weekday(.wide)),
                    subtitle: "\(semesterWeekText(for: today, in: semesterRange)) · 专注当下，把今天过好。"
                )

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    LifeSectionHeader("今日时间轴", subtitle: timeline.isEmpty ? nil : "按时间排列")
                    LifeSurface {
                        if timeline.isEmpty {
                            EmptyInlineView(text: "今天还没有带具体时间的安排。")
                        } else {
                            TimelineList(items: timeline)
                        }
                    }
                }

                HStack(alignment: .top, spacing: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        LifeSectionHeader("今日任务", subtitle: "拖入任务即可安排今天")
                        LifeSurface {
                            if todayTasks.isEmpty {
                                EmptyInlineView(text: isReceivingTodayTask ? "松开即可加入今日任务" : "将右侧任务拖到这里，安排在今天完成。")
                            } else {
                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    ForEach(todayTasks, id: \.id) { task in
                                        TaskRow(task: task, dateStyle: .today) { complete(task) }
                                    }
                                }
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                                .stroke(AppColors.accent, lineWidth: isReceivingTodayTask ? 2 : 0)
                        }
                        .dropDestination(for: String.self) { identifiers, _ in
                            addToToday(identifiers)
                        } isTargeted: { isReceivingTodayTask = $0 }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        LifeSectionHeader("任务列表", subtitle: "按截止日期排序")
                        LifeSurface {
                            if taskList.isEmpty {
                                EmptyInlineView(text: "没有可安排的未完成任务。")
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(taskList, id: \.id) { task in
                                        HStack(spacing: AppSpacing.sm) {
                                            Image(systemName: "flag")
                                                .foregroundStyle(AppColors.deadline)
                                            Text(task.title)
                                                .font(AppTypography.body)
                                                .foregroundStyle(AppColors.primaryText)
                                                .lineLimit(1)
                                            Spacer()
                                            if let deadline = task.deadline {
                                                Text("截止 \(localizedDate(deadline))")
                                                    .font(AppTypography.metadata)
                                                    .foregroundStyle(AppColors.secondaryText)
                                            } else {
                                                Text("未设置截止日期")
                                                    .font(AppTypography.metadata)
                                                    .foregroundStyle(AppColors.secondaryText)
                                            }
                                        }
                                        .padding(.vertical, AppSpacing.xs)
                                        .contentShape(.rect)
                                        .draggable(task.id.uuidString)
                                        if task.id != taskList.last?.id {
                                            Divider().overlay(AppColors.divider.opacity(0.65))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(AppSpacing.page)
        }
        .background(AppColors.canvas)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: today) {
        case 5..<11: "早上好"
        case 11..<14: "中午好"
        case 14..<18: "下午好"
        default: "晚上好"
        }
    }

    private func complete(_ task: Task) {
        task.markCompleted()
        task.assignment?.isCompleted = true
        try? modelContext.save()
    }

    /// Dragging assigns a task to Today through the shared scheduling rule.
    private func addToToday(_ identifiers: [String]) -> Bool {
        let draggedTasks = identifiers.compactMap { identifier in
            UUID(uuidString: identifier).flatMap { id in tasks.first { $0.id == id } }
        }
        guard !draggedTasks.isEmpty else { return false }

        for task in draggedTasks {
            try? InboxCaptureService.schedule(task, on: today, in: modelContext)
        }
        return true
    }

    private func localizedDate(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day())
    }

    private func semesterWeekText(for date: Date, in range: SemesterDateRange) -> String {
        guard let weekNumber = range.weekNumber(containing: date) else { return "当前不在学期内" }
        return "第 \(weekNumber) 周"
    }
}

struct SummaryItem: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        LifeMetric(title: title, value: value, symbol: symbol)
    }
}

// MARK: - Tasks

enum TaskFilter: String, CaseIterable, Identifiable {
    case today = "今天"
    case all = "全部"
    case completed = "已完成"
    var id: String { rawValue }
}

/// A focused task surface: one list, three scopes, and editing only when requested.
struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Task.createdAt, order: .reverse) private var tasks: [Task]
    @State private var filter: TaskFilter = .all
    @State private var editorPresented = false
    @State private var selectedTask: Task?
    @State private var inspectorPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            LifePageHeader(
                eyebrow: nil,
                title: filter.rawValue,
                subtitle: filterSubtitle
            )

            Picker("任务范围", selection: $filter) {
                ForEach(TaskFilter.allCases) { filter in
                    Text("\(filter.rawValue) \(taskCount(for: filter))").tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 440)

            if filteredTasks.isEmpty {
                Spacer()
                EmptyInlineView(text: filter == .completed ? "还没有已完成任务。" : "这里还没有任务，使用右上角“新建任务”开始记录。")
                Spacer()
            } else {
                List {
                    ForEach(filteredTasks, id: \.id) { task in
                        TaskRow(task: task, dateStyle: .taskList) { toggle(task) }
                            .contentShape(.rect)
                            .onTapGesture { openInspector(for: task) }
                            .contextMenu {
                                Button("编辑任务") { openInspector(for: task) }
                                if TaskListGrouping.isScheduled(task, on: .now) {
                                    Button("移出今日任务") { removeFromToday(task) }
                                } else {
                                    Button("设为今日任务") { addToToday(task) }
                                }
                                Divider()
                                Button("删除任务", role: .destructive) { delete(task) }
                            }
                            .listRowInsets(EdgeInsets(top: AppSpacing.xs, leading: AppSpacing.md, bottom: AppSpacing.xs, trailing: AppSpacing.md))
                            .listRowBackground(AppColors.surface.opacity(0.7))
                            .listRowSeparatorTint(AppColors.divider)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(AppSpacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.canvas)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editorPresented = true } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("新建任务")
            }
        }
        .sheet(isPresented: $editorPresented) {
            TaskEditorView()
        }
        .sheet(isPresented: $inspectorPresented) {
            if let selectedTask {
                TaskInspectorView(task: selectedTask, onDelete: {
                    delete(selectedTask)
                    inspectorPresented = false
                })
            }
        }
    }

    private var filteredTasks: [Task] {
        switch filter {
        case .today:
            return tasks.filter { TaskListGrouping.isScheduled($0, on: .now) && $0.status != .completed }
                .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        case .all:
            return tasks.filter { $0.status != .completed }
                .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
        case .completed:
            return tasks.filter { $0.status == .completed }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
    }

    private var filterSubtitle: String {
        switch filter {
        case .today: "今天只保留真正要完成的事项"
        case .all: "按截止日期整理所有未完成任务"
        case .completed: "回顾已经完成的事项"
        }
    }

    private func taskCount(for filter: TaskFilter) -> Int {
        switch filter {
        case .today: return tasks.filter { TaskListGrouping.isScheduled($0, on: .now) && $0.status != .completed }.count
        case .all: return tasks.filter { $0.status != .completed }.count
        case .completed: return tasks.filter { $0.status == .completed }.count
        }
    }

    private func toggle(_ task: Task) {
        task.status == .completed ? task.markActive() : task.markCompleted()
        task.assignment?.isCompleted = task.status == .completed
        try? modelContext.save()
    }

    private func delete(_ task: Task) {
        modelContext.delete(task)
        try? modelContext.save()
    }

    private func openInspector(for task: Task) {
        selectedTask = task
        inspectorPresented = true
    }

    private func removeFromToday(_ task: Task) {
        task.plannedDate = nil
        task.startDate = nil
        task.updatedAt = .now
        try? modelContext.save()
    }

    private func addToToday(_ task: Task) {
        try? InboxCaptureService.schedule(task, on: .now, in: modelContext)
    }
}

enum TaskRowDateStyle {
    case today
    case taskList
}

struct TaskRow: View {
    let task: Task
    let dateStyle: TaskRowDateStyle
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Button(action: toggle) {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.status == .completed ? AppColors.task : AppColors.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.status == .completed ? "标记为未完成" : "标记为完成")

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(task.title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.primaryText)
                    .strikethrough(task.status == .completed)
                    .lineLimit(1)
                if let dateDetail {
                    Label(dateDetail, systemImage: dateSymbol)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
            Spacer()
            Text(task.priority.displayName)
                .font(AppTypography.caption.weight(.medium))
                .foregroundStyle(priorityColor)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var priorityColor: Color {
        switch task.priority {
        case .high: AppColors.deadline
        case .medium: AppColors.deadline.opacity(0.82)
        case .low: AppColors.secondaryText
        }
    }

    private var dateDetail: String? {
        switch dateStyle {
        case .today:
            guard let startDate = task.startDate else { return "今天计划" }
            return startDate.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).hour().minute())
        case .taskList:
            if let deadline = task.deadline {
                return "截止 \(deadline.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day()))"
            }
            if let startDate = task.startDate {
                return "安排 \(startDate.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day().hour().minute()))"
            }
            if let plannedDate = task.plannedDate {
                return "计划 \(plannedDate.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day()))"
            }
            return nil
        }
    }

    private var dateSymbol: String {
        dateStyle == .today && task.startDate != nil ? "clock" : "calendar"
    }
}

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: Task?
    let project: Project?
    @State private var title: String
    @State private var taskDescription: String
    @State private var priority: TaskPriority
    @State private var deadline: Date

    init(task: Task? = nil, project: Project? = nil) {
        self.task = task
        self.project = project
        _title = State(initialValue: task?.title ?? "")
        _taskDescription = State(initialValue: task?.taskDescription ?? "")
        _priority = State(initialValue: task?.priority ?? .medium)
        _deadline = State(initialValue: task?.deadline ?? .now)
    }

    var body: some View {
        Form {
            TextField("任务标题", text: $title)
            TextField("描述（可选）", text: $taskDescription, axis: .vertical)
            Picker("优先级", selection: $priority) {
                ForEach(TaskPriority.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            DatePicker("截止日期", selection: $deadline, displayedComponents: .date)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let task {
            task.title = cleanTitle
            task.taskDescription = taskDescription.nilIfEmpty
            task.priority = priority
            task.deadline = deadline
            if let project { task.project = project }
            task.updatedAt = .now
        } else {
            let newTask = Task(title: cleanTitle, taskDescription: taskDescription.nilIfEmpty, deadline: deadline, priority: priority)
            newTask.project = project
            modelContext.insert(newTask)
        }
        try? modelContext.save()
        dismiss()
    }
}

/// A macOS inspector-style editor for an existing task.
struct TaskInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    let task: Task
    let onDelete: () -> Void
    @State private var title: String
    @State private var taskDescription: String
    @State private var priority: TaskPriority
    @State private var deadline: Date
    @State private var courseID: UUID?
    @State private var savedMessage = ""
    @State private var deleteConfirmationPresented = false

    init(task: Task, onDelete: @escaping () -> Void) {
        self.task = task
        self.onDelete = onDelete
        _title = State(initialValue: task.title)
        _taskDescription = State(initialValue: task.taskDescription ?? "")
        _priority = State(initialValue: task.priority)
        _deadline = State(initialValue: task.deadline ?? .now)
        _courseID = State(initialValue: task.course?.id)
    }

    var body: some View {
        Form {
            Section("任务") {
                TextField("标题", text: $title)
                    .font(.title3.weight(.medium))
                TextField("描述", text: $taskDescription, axis: .vertical)
                    .lineLimit(3...8)
                Picker("优先级", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }

            Section("截止时间") {
                DatePicker("截止日期", selection: $deadline, displayedComponents: .date)
            }

            Section("今日任务") {
                if TaskListGrouping.isScheduled(task, on: .now) {
                    Label("已加入今日任务", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("移出今日任务", role: .destructive, action: removeFromToday)
                } else {
                    Label("将任务安排在今天完成", systemImage: "calendar.badge.plus")
                        .foregroundStyle(.secondary)
                    Button("设为今日任务", action: addToToday)
                }
            }

            Section("关联") {
                Picker("所属课程", selection: $courseID) {
                    Text("未关联课程").tag(UUID?.none)
                    ForEach(courses, id: \.id) { course in
                        Text(course.name).tag(UUID?.some(course.id))
                    }
                }
            }

            Section {
                HStack {
                    Button("删除任务", role: .destructive) { deleteConfirmationPresented = true }
                    Spacer()
                    Text(savedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("保存更改", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 360, maxWidth: 480, alignment: .leading)
        .navigationTitle("任务详情")
        .confirmationDialog("删除任务？", isPresented: $deleteConfirmationPresented, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private func save() {
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.taskDescription = taskDescription.nilIfEmpty
        task.priority = priority
        task.deadline = deadline
        task.course = courses.first { $0.id == courseID }
        task.updatedAt = .now
        try? modelContext.save()
        savedMessage = "已保存"
    }

    private func removeFromToday() {
        task.plannedDate = nil
        task.startDate = nil
        task.updatedAt = .now
        try? modelContext.save()
        savedMessage = "已移出今日任务"
    }

    private func addToToday() {
        try? InboxCaptureService.schedule(task, on: .now, in: modelContext)
        savedMessage = "已设为今日任务"
    }
}

// MARK: - Habits, Projects and Courses

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { TextField("新习惯，例如：阅读", text: $name); Button("添加", action: add).disabled(name.nilIfEmpty == nil) }
            .padding(.horizontal, 24)
            if habits.isEmpty { ContentUnavailableView("还没有习惯", systemImage: "repeat", description: Text("添加一个每天想坚持的小目标。")) }
            else { List(habits, id: \.id) { habit in
                Button { HabitService.toggle(habit, on: .now, in: modelContext) } label: {
                    HStack { Image(systemName: HabitService.isCompleted(habit, on: .now) ? "checkmark.circle.fill" : "circle").foregroundStyle(HabitService.isCompleted(habit, on: .now) ? .green : .secondary); Text(habit.name); Spacer(); Text("\(habit.records.count) 次").foregroundStyle(.secondary) }
                }.buttonStyle(.plain).padding(.vertical, 7)
            }.listStyle(.inset) }
        }.padding(.top, 20)
    }
    private func add() { modelContext.insert(Habit(name: name.trimmingCharacters(in: .whitespacesAndNewlines))); try? modelContext.save(); name = "" }
}

struct StatisticsView: View {
    @Query private var tasks: [Task]
    @Query private var habits: [Habit]
    @Query private var journals: [JournalEntry]
    var body: some View {
        let completed = tasks.filter { $0.status == .completed }.count
        let active = tasks.filter { $0.status != .completed }.count
        let habitToday = habits.filter { HabitService.isCompleted($0, on: .now) }.count
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text("本月回顾").font(.title2.weight(.semibold))
            HStack(spacing: 14) { SummaryItem(title: "任务完成", value: "\(completed) / \(completed + active)", symbol: "checkmark.circle"); SummaryItem(title: "今日习惯", value: "\(habitToday) / \(habits.count)", symbol: "repeat"); SummaryItem(title: "日记天数", value: "\(journals.count)", symbol: "book.closed") }
            GroupBox("使用说明") { Text("统计基于本机任务、习惯和日记实时计算。后续将逐步补充学习时长、趋势和 Life Calendar。") .foregroundStyle(.secondary).padding(.vertical, 4) }
        }.padding(28) }
    }
}

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Task.createdAt, order: .reverse) private var allTasks: [Task]
    @State private var editorPresented = false
    @State private var editingProject: Project?
    @State private var taskProject: Project?

    var body: some View {
        Group {
            if projects.isEmpty {
                ContentUnavailableView("还没有项目", systemImage: "folder", description: Text("点击右上角 ＋ 创建一个长期目标。"))
            } else {
                List {
                    ForEach(projects, id: \.id) { project in
                        let projectTasks = tasks(for: project)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(project.name).font(.headline)
                                Spacer()
                                if project.isArchived { Text("已归档").font(.caption).foregroundStyle(.secondary) }
                                Text(project.completionRate, format: .percent.precision(.fractionLength(0)))
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: project.completionRate)
                            HStack(spacing: 12) {
                                Text("\(projectTasks.filter { $0.status != .completed }.count) 项待完成")
                                if let deadline = project.deadline {
                                    Text(deadline < .now && project.completionRate < 1 ? "已逾期" : "截止 \(deadline.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day()))")
                                        .foregroundStyle(deadline < .now && project.completionRate < 1 ? .red : .secondary)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            DisclosureGroup("项目任务（\(projectTasks.count)）") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(projectTasks, id: \.id) { task in
                                        Button {
                                            task.status == .completed ? task.markActive() : task.markCompleted()
                                            try? modelContext.save()
                                        } label: {
                                            Label(task.title, systemImage: task.status == .completed ? "checkmark.circle.fill" : "circle")
                                                .strikethrough(task.status == .completed)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Button("添加项目任务") { taskProject = project }
                                        .font(.caption.weight(.medium))
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 5)
                        .contextMenu { Button("编辑项目") { editingProject = project }; Button(project.isArchived ? "恢复项目" : "归档项目") { project.isArchived.toggle(); project.updatedAt = .now; try? modelContext.save() }; Divider(); Button("删除项目", role: .destructive) { modelContext.delete(project); try? modelContext.save() } }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editorPresented = true } label: { Label("新建项目", systemImage: "plus") }
                    .accessibilityLabel("新建项目")
            }
        }
        .sheet(isPresented: $editorPresented) { ProjectEditorView() }
        .sheet(item: $editingProject) { ProjectEditorView(project: $0) }
        .sheet(item: $taskProject) { TaskEditorView(project: $0) }
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets { modelContext.delete(projects[offset]) }
        try? modelContext.save()
    }

    private func tasks(for project: Project) -> [Task] {
        allTasks.filter { $0.project?.id == project.id }
    }
}

private struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let project: Project?
    @State private var name: String
    @State private var description = ""
    @State private var hasDeadline = false
    @State private var deadline: Date
    init(project: Project? = nil) { self.project = project; _name = State(initialValue: project?.name ?? ""); _description = State(initialValue: project?.projectDescription ?? ""); _hasDeadline = State(initialValue: project?.deadline != nil); _deadline = State(initialValue: project?.deadline ?? .now) }

    var body: some View {
        Form {
            TextField("项目名称", text: $name)
            TextField("项目说明（可选）", text: $description, axis: .vertical)
            Toggle("设置截止日期", isOn: $hasDeadline)
            if hasDeadline { DatePicker("截止日期", selection: $deadline, displayedComponents: .date) }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(project == nil ? "创建" : "保存", action: save).disabled(name.nilIfEmpty == nil) }
        }
    }

    private func save() {
        if let project { project.name = name.trimmingCharacters(in: .whitespacesAndNewlines); project.projectDescription = description.nilIfEmpty; project.deadline = hasDeadline ? deadline : nil; project.updatedAt = .now } else { modelContext.insert(Project(name: name.trimmingCharacters(in: .whitespacesAndNewlines), projectDescription: description.nilIfEmpty, deadline: hasDeadline ? deadline : nil)) }
        try? modelContext.save()
        dismiss()
    }
}

/// The timetable is a dedicated page so weekly planning is never mixed with course administration.
struct TimetableView: View {
    @Query(sort: \Course.name) private var courses: [Course]

    var body: some View {
        CourseTimetableView(courses: courses)
    }
}

struct CoursesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    @State private var selectedID: UUID?
    @State private var editorPresented = false
    @State private var editingCourse: Course?

    var body: some View {
        Group {
            if let course = selectedCourse {
                CourseDetailView(course: course) {
                    editingCourse = course
                    editorPresented = true
                } onDelete: {
                    delete(course)
                }
            } else {
                CourseLibraryView(
                    courses: courses,
                    onSelect: { selectedID = $0.id },
                    onEdit: { course in
                        editingCourse = course
                        editorPresented = true
                    },
                    onCreate: createCourse
                )
            }
        }
        .background(AppColors.canvas)
        .toolbar {
            if selectedCourse != nil {
                ToolbarItem(placement: .navigation) {
                    Button {
                        selectedID = nil
                    } label: {
                        Label("全部课程", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("返回课程列表")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: createCourse) { Label("新建课程", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $editorPresented) { CourseEditorView(course: editingCourse) }
    }

    private func delete(_ course: Course) {
        if selectedID == course.id { selectedID = nil }
        modelContext.delete(course)
        try? modelContext.save()
    }

    private func createCourse() {
        editingCourse = nil
        editorPresented = true
    }

    private var selectedCourse: Course? {
        courses.first(where: { $0.id == selectedID })
    }
}

private struct CourseLibraryView: View {
    let courses: [Course]
    let onSelect: (Course) -> Void
    let onEdit: (Course) -> Void
    let onCreate: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 270, maximum: 440), spacing: AppSpacing.lg, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                LifePageHeader(
                    eyebrow: "知识空间",
                    title: "我的课程",
                    subtitle: courses.isEmpty ? "先新建一门课程，开始整理你的学习节奏。" : "选择今天想学习或维护的科目。"
                )

                if courses.isEmpty {
                    ContentUnavailableView {
                        Label("还没有课程", systemImage: "graduationcap")
                    } description: {
                        Text("新建课程后，可设置课程图标、上课时间、作业和考试。")
                    } actions: {
                        Button("新建课程", action: onCreate)
                    }
                    .frame(maxWidth: .infinity, minHeight: 340)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.lg) {
                        ForEach(courses, id: \.id) { course in
                            CourseLibraryCard(course: course, onSelect: { onSelect(course) }, onEdit: { onEdit(course) })
                        }
                    }
                }
            }
            .padding(AppSpacing.page)
            .frame(maxWidth: 1_120, alignment: .leading)
        }
    }
}

private struct CourseLibraryCard: View {
    let course: Course
    let onSelect: () -> Void
    let onEdit: () -> Void
    @State private var isHovered = false

    private var tint: Color { Color(courseHex: course.colorHex) }
    private var completedAssignments: Int {
        course.assignments.filter { $0.isCompleted || $0.linkedTask?.status == .completed }.count
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        CourseIconView(identifier: course.symbolName, tint: tint, size: 46)
                        Spacer(minLength: AppSpacing.sm)
                        Text(progressText)
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(tint.opacity(0.12), in: Capsule())
                            .padding(.trailing, 36)
                    }
                    .padding(AppSpacing.lg)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .background(tint.opacity(isHovered ? 0.17 : 0.11))

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(course.instructor ?? "自主学习")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.secondaryText)
                        Text(course.name)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(AppColors.primaryText)
                            .multilineTextAlignment(.leading)
                        Text(sessionSummary)
                            .font(AppTypography.metadata)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                        Rectangle()
                            .fill(AppColors.divider.opacity(0.55))
                            .frame(height: 1)
                            .padding(.vertical, AppSpacing.xs)
                        HStack {
                            Text(workSummary)
                            Spacer(minLength: AppSpacing.sm)
                            Text("进入课程 →")
                                .foregroundStyle(AppColors.accent)
                        }
                        .font(AppTypography.caption.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                    }
                    .padding(AppSpacing.lg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.extraLarge, style: .continuous)
                        .stroke(isHovered ? tint.opacity(0.55) : AppColors.surfaceBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开课程：\(course.name)")

            Menu {
                Button("编辑课程", systemImage: "pencil", action: onEdit)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(AppColors.surface.opacity(0.9), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .padding(AppSpacing.md)
            .accessibilityLabel("编辑\(course.name)的图标与资料")
        }
        .onHover { isHovered = $0 }
    }

    private var progressText: String {
        guard !course.assignments.isEmpty else { return "准备中" }
        return "作业 \(completedAssignments)/\(course.assignments.count)"
    }

    private var workSummary: String {
        let pendingAssignments = max(0, course.assignments.count - completedAssignments)
        let pieces = [
            pendingAssignments > 0 ? "\(pendingAssignments) 项待办" : nil,
            course.exams.isEmpty ? nil : "\(course.exams.count) 场考试"
        ].compactMap { $0 }
        return pieces.isEmpty ? "还没有作业与考试" : pieces.joined(separator: " · ")
    }

    private var sessionSummary: String {
        guard let session = CourseSessionOrdering.sorted(course.sessions).first else { return "暂未设置课程时间" }
        return "下次课 · 周\(weekdayTitle(session.weekday)) \(timeText(session.startTimeMinutes))–\(timeText(session.endTimeMinutes))"
    }

    private func weekdayTitle(_ weekday: Weekday) -> String {
        ["日", "一", "二", "三", "四", "五", "六"][weekday.rawValue - 1]
    }

    private func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

private struct CourseIconView: View {
    let identifier: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        Group {
            if let text = CourseIcon.customText(from: identifier) {
                Text(text)
                    .font(.system(size: size * 0.48))
            } else {
                Image(systemName: CourseIcon.systemSymbolName(from: identifier))
                    .font(.system(size: size * 0.46, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .foregroundStyle(tint)
        .frame(width: size, height: size)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityLabel("课程图标")
    }
}

private extension Color {
    init(courseHex: String) {
        let value = courseHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else {
            self = AppColors.course
            return
        }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

private struct CourseColorOption: Identifiable {
    let hex: String
    let name: String
    var id: String { hex }

    static let all = [
        CourseColorOption(hex: "#6E889A", name: "蓝灰"),
        CourseColorOption(hex: "#8A7B99", name: "雾紫"),
        CourseColorOption(hex: "#B07A68", name: "陶土"),
        CourseColorOption(hex: "#B69467", name: "暖杏"),
        CourseColorOption(hex: "#7D8F72", name: "鼠尾草")
    ]
}

private struct CourseIconOption: Identifiable {
    let symbolName: String
    let name: String
    var id: String { symbolName }

    static let all = [
        CourseIconOption(symbolName: "graduationcap", name: "通用"),
        CourseIconOption(symbolName: "book.closed", name: "阅读"),
        CourseIconOption(symbolName: "function", name: "数学"),
        CourseIconOption(symbolName: "sum", name: "统计"),
        CourseIconOption(symbolName: "atom", name: "物理"),
        CourseIconOption(symbolName: "flask", name: "化学"),
        CourseIconOption(symbolName: "testtube.2", name: "实验"),
        CourseIconOption(symbolName: "bolt", name: "电路"),
        CourseIconOption(symbolName: "cpu", name: "计算"),
        CourseIconOption(symbolName: "terminal", name: "编程"),
        CourseIconOption(symbolName: "chart.bar", name: "图表"),
        CourseIconOption(symbolName: "globe", name: "地理"),
        CourseIconOption(symbolName: "character.book.closed", name: "语言"),
        CourseIconOption(symbolName: "film", name: "影像"),
        CourseIconOption(symbolName: "music.note", name: "音乐"),
        CourseIconOption(symbolName: "paintpalette", name: "艺术"),
        CourseIconOption(symbolName: "figure.run", name: "运动"),
        CourseIconOption(symbolName: "heart", name: "健康"),
        CourseIconOption(symbolName: "leaf", name: "自然"),
        CourseIconOption(symbolName: "hammer", name: "工程"),
        CourseIconOption(symbolName: "ruler", name: "设计"),
        CourseIconOption(symbolName: "lightbulb", name: "灵感"),
        CourseIconOption(symbolName: "camera", name: "摄影"),
        CourseIconOption(symbolName: "brain.head.profile", name: "思考")
    ]
}

struct CourseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: Course?
    @State private var name: String
    @State private var instructor: String
    @State private var classroom: String
    @State private var semester: String
    @State private var note: String
    @State private var colorHex: String
    @State private var symbolName: String
    @State private var customIconText: String
    @State private var usesSemesterDateRange: Bool
    @State private var courseStartDate: Date
    @State private var courseEndDate: Date

    init(course: Course? = nil) {
        let semesterRange = SemesterDateRangeStore.load()
        let effectiveRange = course?.effectiveDateRange(semesterRange: semesterRange) ?? semesterRange
        let storedSymbolName = course?.symbolName ?? CourseIcon.defaultSymbolName
        self.course = course
        _name = State(initialValue: course?.name ?? "")
        _instructor = State(initialValue: course?.instructor ?? "")
        _classroom = State(initialValue: course?.classroom ?? "")
        _semester = State(initialValue: course?.semester ?? "")
        _note = State(initialValue: course?.note ?? "")
        _colorHex = State(initialValue: course?.colorHex ?? "#6E889A")
        _symbolName = State(initialValue: CourseIcon.customText(from: storedSymbolName) == nil ? storedSymbolName : CourseIcon.defaultSymbolName)
        _customIconText = State(initialValue: CourseIcon.customText(from: storedSymbolName) ?? "")
        _usesSemesterDateRange = State(initialValue: course?.usesSemesterDateRange ?? true)
        _courseStartDate = State(initialValue: effectiveRange.startDate)
        _courseEndDate = State(initialValue: effectiveRange.endDate)
    }

    var body: some View {
        Form {
            Section("课程信息") {
                TextField("课程名称", text: $name)
                TextField("教师（可选）", text: $instructor)
                TextField("教室（可选）", text: $classroom)
                TextField("学期（可选）", text: $semester)
                TextField("课程备注（可选）", text: $note, axis: .vertical)
            }

            Section("课程图标") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.xs), count: 6), spacing: AppSpacing.xs) {
                    ForEach(CourseIconOption.all) { option in
                        Button {
                            symbolName = option.symbolName
                            customIconText = ""
                        } label: {
                            Image(systemName: option.symbolName)
                                .font(.system(size: 17, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(symbolName == option.symbolName && customIconText.isEmpty ? AppColors.surface : AppColors.course)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(
                                    symbolName == option.symbolName && customIconText.isEmpty ? AppColors.course : AppColors.course.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(option.name)
                        .accessibilityLabel("选择\(option.name)图标")
                    }
                }

                HStack(spacing: AppSpacing.sm) {
                    CourseIconView(identifier: resolvedSymbolName, tint: Color(courseHex: colorHex), size: 32)
                    TextField("自定义图标（例如 🧪 或 研）", text: $customIconText)
                        .onChange(of: customIconText) { _, text in
                            if CourseIcon.customIdentifier(from: text) != nil {
                                symbolName = CourseIcon.defaultSymbolName
                            }
                        }
                }
                Text("可输入最多 4 个字符或 Emoji；留空时使用上方选择的系统图标。")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }

            Section("外观") {
                Picker("课程颜色", selection: $colorHex) {
                    ForEach(CourseColorOption.all) { option in
                        Text(option.name).tag(option.hex)
                    }
                }
            }

            Section("课程日期") {
                Toggle("跟随课表学期日期", isOn: $usesSemesterDateRange)
                Text("关闭后可为本课程单独设置起止日期，不影响其他课程。")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
                if usesSemesterDateRange {
                    Text(dateRangeText(SemesterDateRangeStore.load()))
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                } else {
                    DatePicker("开始日期", selection: $courseStartDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $courseEndDate, in: courseStartDate..., displayedComponents: .date)
                }
            }
        }
        .formStyle(.grouped).padding().frame(width: 520)
        .navigationTitle(course == nil ? "新建课程" : "编辑课程")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(name.nilIfEmpty == nil || (!usesSemesterDateRange && courseEndDate < courseStartDate))
            }
        }
    }
    private func save() {
        let selectedRange = usesSemesterDateRange
            ? SemesterDateRangeStore.load()
            : SemesterDateRange(startDate: courseStartDate, endDate: courseEndDate)
        if let course {
            course.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            course.instructor = instructor.nilIfEmpty
            course.classroom = classroom.nilIfEmpty
            course.semester = semester.nilIfEmpty
            course.note = note.nilIfEmpty
            course.colorHex = colorHex
            course.symbolName = resolvedSymbolName
            course.setDateRange(selectedRange, usesSemesterRange: usesSemesterDateRange)
        } else {
            let newCourse = Course(name: name.trimmingCharacters(in: .whitespacesAndNewlines), instructor: instructor.nilIfEmpty, classroom: classroom.nilIfEmpty, colorHex: colorHex, symbolName: resolvedSymbolName, semester: semester.nilIfEmpty, note: note.nilIfEmpty)
            newCourse.setDateRange(selectedRange, usesSemesterRange: usesSemesterDateRange)
            modelContext.insert(newCourse)
        }
        try? modelContext.save(); dismiss()
    }

    private var resolvedSymbolName: String {
        CourseIcon.customIdentifier(from: customIconText) ?? symbolName
    }

    private func dateRangeText(_ range: SemesterDateRange) -> String {
        "\(localizedDate(range.startDate))–\(localizedDate(range.endDate))"
    }

    private func localizedDate(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day())
    }
}

struct CourseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let course: Course
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var sessionEditor = false
    @State private var sessionEditPresented = false
    @State private var editingSession: CourseSession?
    @State private var sessionDeleteConfirmationPresented = false
    @State private var sessionPendingDeletion: CourseSession?
    @State private var assignmentEditor = false
    @State private var examEditor = false
    @State private var deleteConfirmationPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                HStack(spacing: AppSpacing.md) {
                    CourseIconView(identifier: course.symbolName, tint: Color(courseHex: course.colorHex), size: 46)
                    LifePageHeader(eyebrow: nil, title: course.name, subtitle: nil)
                }

                detailSection("课程信息") {
                            if let instructor = course.instructor { detailRow("教师", value: instructor) }
                            if let classroom = course.classroom { detailRow("教室", value: classroom) }
                            if let semester = course.semester { detailRow("学期", value: semester) }
                            detailRow("日期", value: courseDateRangeText)
                            if let note = visibleCourseNote {
                                Text(note)
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColors.secondaryText)
                                    .padding(.top, AppSpacing.xxs)
                            }
                        }

                detailSection("课程时间", actionTitle: "添加课程时间") { sessionEditor = true } content: {
                            if course.sessions.isEmpty {
                                Text("尚未添加上课时间。")
                                    .font(AppTypography.metadata)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            ForEach(CourseSessionOrdering.sorted(course.sessions), id: \.id) { session in
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "clock")
                                        .foregroundStyle(AppColors.course)
                                    Text("周\(weekdayName(session.weekday)) · \(timeText(session.startTimeMinutes))–\(timeText(session.endTimeMinutes))")
                                        .font(AppTypography.body)
                                    Text(session.weekPattern.displayName)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.secondaryText)
                                    Spacer()
                                    Button {
                                        editingSession = session
                                        sessionEditPresented = true
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("编辑这条课程时间")

                                    Button(role: .destructive) {
                                        sessionPendingDeletion = session
                                        sessionDeleteConfirmationPresented = true
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("删除课程时间")
                                    .accessibilityLabel("删除这条课程时间")
                                }
                            }
                        }

                detailSection("作业", actionTitle: "添加作业") { assignmentEditor = true } content: {
                            if course.assignments.isEmpty {
                                Text("还没有作业记录。")
                                    .font(AppTypography.metadata)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            ForEach(course.assignments, id: \.id) { assignment in
                                HStack {
                                    Text(assignment.title).font(AppTypography.body)
                                    Spacer()
                                    Text(assignment.linkedTask?.status == .completed ? "已完成" : "待完成")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(assignment.linkedTask?.status == .completed ? AppColors.task : AppColors.secondaryText)
                                }
                            }
                        }

                detailSection("考试", actionTitle: "添加考试") { examEditor = true } content: {
                            if course.exams.isEmpty {
                                Text("还没有考试记录。")
                                    .font(AppTypography.metadata)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            ForEach(course.exams, id: \.id) { exam in
                                HStack {
                                    Text(exam.title).font(AppTypography.body)
                                    Spacer()
                                    Text(exam.startDate.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day().hour().minute()))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                            }
                        }
            }
            .padding(AppSpacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.canvas)
        .toolbar {
            ToolbarItem {
                Button(action: onEdit) {
                    Label("编辑课程", systemImage: "pencil")
                }
            }
            ToolbarItem {
                Button(role: .destructive) {
                    deleteConfirmationPresented = true
                } label: {
                    Label("删除课程", systemImage: "trash")
                }
                .accessibilityLabel("删除当前课程")
            }
        }
        .confirmationDialog("删除“\(course.name)”？", isPresented: $deleteConfirmationPresented, titleVisibility: .visible) {
            Button("删除课程", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        } message: {
            Text("课程的课次、作业和考试记录也会一并删除。")
        }
        .confirmationDialog(
            "删除这条课程时间？",
            isPresented: $sessionDeleteConfirmationPresented,
            titleVisibility: .visible,
            presenting: sessionPendingDeletion
        ) { session in
            Button("删除课程时间", role: .destructive) {
                deleteSession(session)
            }
            Button("取消", role: .cancel) {
                sessionPendingDeletion = nil
            }
        } message: { session in
            Text("将删除周\(weekdayName(session.weekday)) \(timeText(session.startTimeMinutes))–\(timeText(session.endTimeMinutes)) 的课程时间，删除后无法恢复。")
        }
        .sheet(isPresented: $sessionEditor) { CourseSessionEditor(initialCourse: course) }
        .sheet(isPresented: $sessionEditPresented) {
            if let editingSession {
                CourseSessionEditor(session: editingSession)
            }
        }
        .sheet(isPresented: $assignmentEditor) { AssignmentEditor(course: course) }
        .sheet(isPresented: $examEditor) { ExamEditor(course: course) }
    }

    private func weekdayName(_ weekday: Weekday) -> String { ["日", "一", "二", "三", "四", "五", "六"][weekday.rawValue - 1] }
    private func timeText(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    private var visibleCourseNote: String? {
        guard let note = course.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              note.hasPrefix("截图原始信息：") == false
        else { return nil }
        return note.nilIfEmpty
    }

    private var courseDateRangeText: String {
        let range = course.effectiveDateRange(semesterRange: SemesterDateRangeStore.load())
        let formatter = Date.FormatStyle.dateTime
            .locale(Locale(identifier: "zh_CN"))
            .year().month().day()
        return "\(range.startDate.formatted(formatter))–\(range.endDate.formatted(formatter))"
    }

    private func deleteSession(_ session: CourseSession) {
        sessionPendingDeletion = nil
        if editingSession?.id == session.id {
            editingSession = nil
            sessionEditPresented = false
        }
        modelContext.delete(session)
        course.updatedAt = .now
        try? modelContext.save()
    }

    @ViewBuilder
    private func detailSection<Content: View>(
        _ title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                LifeSectionHeader(title)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderless)
                        .foregroundStyle(AppColors.accent)
                }
            }
            LifeSurface(padding: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.sm, content: content)
            }
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.metadata)
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.primaryText)
        }
    }
}

struct TimetableSlot {
    let weekday: Weekday
    let startTimeMinutes: Int
    let endTimeMinutes: Int
}

struct TimetablePeriodSpan: Equatable {
    let startIndex: Int
    let endIndex: Int

    var rowCount: Int { endIndex - startIndex + 1 }
}

struct TimetablePlacementInput: Equatable {
    let id: UUID
    let dayIndex: Int
    let startIndex: Int
    let endIndex: Int
}

struct TimetableLanePlacement: Equatable {
    let laneIndex: Int
    let laneCount: Int
}

enum TimetableLayout {
    /// Returns every configured period touched by a session. Breaks between the
    /// first and last touched periods remain part of the visual course block.
    static func periodSpan(
        startTimeMinutes: Int,
        endTimeMinutes: Int,
        periods: [TimetablePeriod]
    ) -> TimetablePeriodSpan? {
        guard endTimeMinutes > startTimeMinutes else { return nil }

        let overlappingIndices = periods.indices.filter { index in
            startTimeMinutes < periods[index].endTimeMinutes
                && endTimeMinutes > periods[index].startTimeMinutes
        }

        guard let first = overlappingIndices.first,
              let last = overlappingIndices.last
        else { return nil }

        return TimetablePeriodSpan(startIndex: first, endIndex: last)
    }

    /// Places overlapping sessions in parallel lanes instead of drawing them
    /// over each other. Connected collision groups share the same lane count.
    static func lanePlacements(
        for inputs: [TimetablePlacementInput]
    ) -> [UUID: TimetableLanePlacement] {
        var result: [UUID: TimetableLanePlacement] = [:]

        for dayInputs in Dictionary(grouping: inputs, by: \.dayIndex).values {
            let sorted = dayInputs.sorted {
                if $0.startIndex != $1.startIndex { return $0.startIndex < $1.startIndex }
                if $0.endIndex != $1.endIndex { return $0.endIndex < $1.endIndex }
                return $0.id.uuidString < $1.id.uuidString
            }
            var component: [TimetablePlacementInput] = []
            var componentEnd = -1

            func placeComponent(_ items: [TimetablePlacementInput]) {
                guard !items.isEmpty else { return }
                var laneEnds: [Int] = []
                var assigned: [(id: UUID, laneIndex: Int)] = []

                for item in items {
                    if let availableLane = laneEnds.firstIndex(where: { $0 < item.startIndex }) {
                        laneEnds[availableLane] = item.endIndex
                        assigned.append((item.id, availableLane))
                    } else {
                        laneEnds.append(item.endIndex)
                        assigned.append((item.id, laneEnds.count - 1))
                    }
                }

                let laneCount = laneEnds.count
                for assignment in assigned {
                    result[assignment.id] = TimetableLanePlacement(
                        laneIndex: assignment.laneIndex,
                        laneCount: laneCount
                    )
                }
            }

            for item in sorted {
                if component.isEmpty || item.startIndex <= componentEnd {
                    component.append(item)
                    componentEnd = max(componentEnd, item.endIndex)
                } else {
                    placeComponent(component)
                    component = [item]
                    componentEnd = item.endIndex
                }
            }
            placeComponent(component)
        }

        return result
    }
}

enum TimetableWeekFilter: String, CaseIterable, Identifiable {
    case all
    case odd
    case even

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "全部"
        case .odd: "单周"
        case .even: "双周"
        }
    }

    func includes(_ pattern: WeekPattern) -> Bool {
        switch self {
        case .all: true
        case .odd: pattern == .all || pattern == .odd
        case .even: pattern == .all || pattern == .even
        }
    }

    static func preferred(
        for date: Date,
        semesterRange: SemesterDateRange,
        calendar: Calendar = .current
    ) -> TimetableWeekFilter {
        guard let weekNumber = semesterRange.weekNumber(containing: date, calendar: calendar) else { return .all }
        return weekNumber.isMultiple(of: 2) ? .even : .odd
    }
}

/// A weekly timetable editor backed directly by CourseSession recurrence rules.
struct CourseTimetableView: View {
    @Environment(\.modelContext) private var modelContext
    let courses: [Course]
    @State private var selectedSlot: TimetableSlot?
    @State private var periods = TimetablePeriodStore.load()
    @State private var periodSettingsPresented = false
    @State private var semesterSettingsPresented = false
    @State private var semesterRange: SemesterDateRange
    @State private var weekFilter: TimetableWeekFilter
    @State private var zoomScale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1
    private let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    private struct LayoutMetrics {
        let timeColumnWidth: CGFloat
        let dayColumnWidth: CGFloat
        let headerHeight: CGFloat
        let rowHeight: CGFloat
        let periodCount: Int

        var contentWidth: CGFloat { timeColumnWidth + dayColumnWidth * 7 }
        var contentHeight: CGFloat { headerHeight + rowHeight * CGFloat(periodCount) }
    }

    private struct CourseBlock: Identifiable {
        let course: Course
        let session: CourseSession
        let dayIndex: Int
        let periodSpan: TimetablePeriodSpan

        var id: UUID { session.id }
    }

    init(courses: [Course]) {
        let range = SemesterDateRangeStore.load()
        self.courses = courses
        _semesterRange = State(initialValue: range)
        _weekFilter = State(initialValue: .preferred(for: .now, semesterRange: range))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                LifePageHeader(
                    eyebrow: nil,
                    title: "本周课程",
                    subtitle: "\(currentSemesterWeekText) · 按节次查看每周安排，双指捏合可缩放课表"
                )

                Spacer(minLength: AppSpacing.md)

                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Picker("显示周次", selection: $weekFilter) {
                        ForEach(TimetableWeekFilter.allCases) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    Text("缩放 " + String(Int(effectiveZoomScale * 100)) + "%")
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(AppColors.secondaryText.opacity(0.72))
                }
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.vertical, AppSpacing.md)

            Group {
                if courses.isEmpty {
                    EmptyInlineView(text: "先添加一门课程，即可在课表空白节次添加课程时间。")
                } else if periods.isEmpty {
                    EmptyInlineView(text: "还没有课表节次。请使用右上角“节次设置”添加每节课的开始和结束时间。")
                } else {
                    GeometryReader { proxy in
                        let fittedSize = CGSize(
                            width: max(1, proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing),
                            height: max(1, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom)
                        )
                        let metrics = layoutMetrics(for: fittedSize)

                        ScrollView([.horizontal, .vertical]) {
                            timetableGrid(metrics: metrics)
                                .frame(
                                    width: metrics.contentWidth,
                                    height: metrics.contentHeight,
                                    alignment: .topLeading
                                )
                                .background(AppColors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                                        .stroke(AppColors.surfaceBorder, lineWidth: 1)
                                }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .simultaneousGesture(zoomGesture)
                        .accessibilityAction(named: "恢复课表缩放") {
                            withAnimation(.easeOut(duration: 0.18)) { zoomScale = 1 }
                        }
                    }
                    .padding(.horizontal, AppSpacing.page)
                    .padding(.bottom, AppSpacing.page)
                }
            }
        }
        .background(AppColors.canvas)
        .sheet(item: $selectedSlot) { slot in
            CourseSessionEditor(
                initialCourse: nil,
                initialWeekday: slot.weekday,
                initialStartTimeMinutes: slot.startTimeMinutes,
                initialEndTimeMinutes: slot.endTimeMinutes
            )
        }
        .sheet(isPresented: $periodSettingsPresented) {
            TimetablePeriodSettingsView(periods: $periods)
        }
        .sheet(isPresented: $semesterSettingsPresented) {
            SemesterDateSettingsView(range: semesterRange, onSave: applySemesterRange)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { semesterSettingsPresented = true } label: {
                    Label("学期设置", systemImage: "calendar.badge.clock")
                }
                .accessibilityLabel("设置学期开始和结束日期")

                Button { periodSettingsPresented = true } label: {
                    Label("节次设置", systemImage: "slider.horizontal.3")
                }
                .accessibilityLabel("设置课表节次时间")
            }
        }
    }

    private var currentSemesterWeekText: String {
        guard let weekNumber = semesterRange.weekNumber(containing: .now) else { return "当前不在学期内" }
        return "第 \(weekNumber) 周"
    }

    private func applySemesterRange(_ range: SemesterDateRange) {
        SemesterDateRangeStore.save(range)
        semesterRange = range
        SemesterDateRangeCoordinator.applyGlobalRange(range, to: courses)
        weekFilter = .preferred(for: .now, semesterRange: range)
        try? modelContext.save()
    }

    private var effectiveZoomScale: CGFloat {
        clampedZoom(zoomScale * gestureScale)
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                zoomScale = clampedZoom(zoomScale * value)
            }
    }

    private var visibleCourseBlocks: [CourseBlock] {
        courses.flatMap { course in
            course.sessions.compactMap { session -> CourseBlock? in
                guard session.recurrenceEnabled,
                      weekFilter.includes(session.weekPattern),
                      let dayIndex = weekdays.firstIndex(of: session.weekday),
                      let span = TimetableLayout.periodSpan(
                        startTimeMinutes: session.startTimeMinutes,
                        endTimeMinutes: session.endTimeMinutes,
                        periods: periods
                      )
                else { return nil }

                return CourseBlock(
                    course: course,
                    session: session,
                    dayIndex: dayIndex,
                    periodSpan: span
                )
            }
        }
        .sorted {
            if $0.dayIndex != $1.dayIndex { return $0.dayIndex < $1.dayIndex }
            return $0.session.startTimeMinutes < $1.session.startTimeMinutes
        }
    }

    private func layoutMetrics(for viewportSize: CGSize) -> LayoutMetrics {
        let zoom = effectiveZoomScale
        let availableWidth = max(1, viewportSize.width)
        let availableHeight = max(1, viewportSize.height)
        let baseTimeColumnWidth = min(96, max(72, availableWidth * 0.075))
        let baseHeaderHeight: CGFloat = 44
        let baseDayColumnWidth = max(1, (availableWidth - baseTimeColumnWidth) / CGFloat(weekdays.count))
        let baseRowHeight = max(1, (availableHeight - baseHeaderHeight) / CGFloat(max(periods.count, 1)))

        return LayoutMetrics(
            timeColumnWidth: baseTimeColumnWidth * zoom,
            dayColumnWidth: baseDayColumnWidth * zoom,
            headerHeight: baseHeaderHeight * zoom,
            rowHeight: baseRowHeight * zoom,
            periodCount: periods.count
        )
    }

    @ViewBuilder
    private func timetableGrid(metrics: LayoutMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            Text("时间")
                .font(AppTypography.caption.weight(.medium))
                .foregroundStyle(AppColors.secondaryText.opacity(0.72))
                .frame(width: metrics.timeColumnWidth, height: metrics.headerHeight)
                .background(AppColors.sidebar.opacity(0.78))

            ForEach(Array(weekdays.enumerated()), id: \.element) { dayIndex, weekday in
                Text(weekdayTitle(weekday))
                    .font(AppTypography.metadata.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: metrics.dayColumnWidth, height: metrics.headerHeight)
                    .background(AppColors.sidebar.opacity(0.78))
                    .offset(
                        x: metrics.timeColumnWidth + CGFloat(dayIndex) * metrics.dayColumnWidth,
                        y: 0
                    )
            }

            ForEach(Array(periods.enumerated()), id: \.element.id) { periodIndex, period in
                periodLabel(period, metrics: metrics)
                    .offset(x: 0, y: metrics.headerHeight + CGFloat(periodIndex) * metrics.rowHeight)

                ForEach(Array(weekdays.enumerated()), id: \.element) { dayIndex, weekday in
                    Button {
                        selectedSlot = TimetableSlot(
                            weekday: weekday,
                            startTimeMinutes: period.startTimeMinutes,
                            endTimeMinutes: period.endTimeMinutes
                        )
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: metrics.dayColumnWidth, height: metrics.rowHeight)
                    .background(AppColors.sidebar.opacity(0.48))
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(AppColors.divider.opacity(0.55))
                            .frame(width: 1)
                    }
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(AppColors.divider.opacity(0.55))
                            .frame(height: 1)
                    }
                    .offset(
                        x: metrics.timeColumnWidth + CGFloat(dayIndex) * metrics.dayColumnWidth,
                        y: metrics.headerHeight + CGFloat(periodIndex) * metrics.rowHeight
                    )
                    .accessibilityLabel("在\(weekdayTitle(weekday)) \(period.name) 添加课程时间")
                }
            }

            let placements = TimetableLayout.lanePlacements(
                for: visibleCourseBlocks.map {
                    TimetablePlacementInput(
                        id: $0.id,
                        dayIndex: $0.dayIndex,
                        startIndex: $0.periodSpan.startIndex,
                        endIndex: $0.periodSpan.endIndex
                    )
                }
            )

            ForEach(visibleCourseBlocks) { block in
                let placement = placements[block.id] ?? TimetableLanePlacement(laneIndex: 0, laneCount: 1)
                let laneWidth = courseLaneWidth(placement: placement, metrics: metrics)

                courseCard(block, width: laneWidth, metrics: metrics)
                    .offset(
                        x: metrics.timeColumnWidth
                            + CGFloat(block.dayIndex) * metrics.dayColumnWidth
                            + 3
                            + CGFloat(placement.laneIndex) * (laneWidth + 2),
                        y: metrics.headerHeight + CGFloat(block.periodSpan.startIndex) * metrics.rowHeight + 3
                    )
                    .zIndex(2)
            }
        }
        .contentShape(Rectangle())
    }

    private func periodLabel(_ period: TimetablePeriod, metrics: LayoutMetrics) -> some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
            Text(period.name)
                .font(AppTypography.caption.weight(.semibold))
            Text("\(timeText(period.startTimeMinutes))–\(timeText(period.endTimeMinutes))")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(AppColors.secondaryText)
        .padding(.trailing, AppSpacing.sm)
        .frame(width: metrics.timeColumnWidth, height: metrics.rowHeight, alignment: .trailing)
        .background(AppColors.sidebar.opacity(0.68))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.divider.opacity(0.55))
                .frame(height: 1)
        }
    }

    private func courseLaneWidth(placement: TimetableLanePlacement, metrics: LayoutMetrics) -> CGFloat {
        let innerWidth = max(1, metrics.dayColumnWidth - 6)
        let gaps = CGFloat(max(placement.laneCount - 1, 0)) * 2
        return max(1, (innerWidth - gaps) / CGFloat(max(placement.laneCount, 1)))
    }

    private func courseCard(_ block: CourseBlock, width: CGFloat, metrics: LayoutMetrics) -> some View {
        let cardHeight = metrics.rowHeight * CGFloat(block.periodSpan.rowCount) - 6
        let compact = width < 125 || metrics.rowHeight < 58
        let titleSize: CGFloat = compact ? 9.5 : 12
        let detailSize: CGFloat = compact ? 8.5 : 10

        return courseCardText(block, titleSize: titleSize, detailSize: detailSize)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(AppColors.primaryText)
            .padding(compact ? 5 : AppSpacing.xs)
            .frame(width: width, height: cardHeight, alignment: .topLeading)
            .clipped()
            .background(
                color(hex: block.course.colorHex).opacity(0.17),
                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(color(hex: block.course.colorHex).opacity(0.52), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(block.course.name)，\(weekdayTitle(block.session.weekday))，\(timeText(block.session.startTimeMinutes))到\(timeText(block.session.endTimeMinutes))，\(block.session.weekPattern.displayName)"
            )
    }

    private func courseCardText(
        _ block: CourseBlock,
        titleSize: CGFloat,
        detailSize: CGFloat
    ) -> Text {
        var text = Text(block.course.name)
            .font(.system(size: titleSize, weight: .semibold))
        text = text + Text("\n\(timeText(block.session.startTimeMinutes))–\(timeText(block.session.endTimeMinutes))")
            .font(.system(size: detailSize, weight: .medium, design: .monospaced))

        if weekFilter == .all || block.session.weekPattern != .all {
            text = text + Text("\n\(block.session.weekPattern.displayName)")
                .font(.system(size: detailSize, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
        }

        if let room = block.session.classroomOverride ?? block.course.classroom {
            text = text + Text("\n\(room)")
                .font(.system(size: detailSize))
        }
        return text
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.72), 1.8)
    }

    private func weekdayTitle(_ weekday: Weekday) -> String { "周\(["一", "二", "三", "四", "五", "六", "日"][weekday.rawValue == 1 ? 6 : weekday.rawValue - 2])" }
    private func timeText(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    private func color(hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt64(trimmed, radix: 16) else { return AppColors.course }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

extension TimetableSlot: Identifiable {
    var id: String { "\(weekday.rawValue)-\(startTimeMinutes)-\(endTimeMinutes)" }
}

struct CourseSessionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Course.name) private var courses: [Course]
    let session: CourseSession?
    let initialCourse: Course?
    @State private var courseID: UUID?
    @State private var weekday: Weekday
    @State private var weekPattern: WeekPattern
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var usesSemesterDateRange: Bool
    @State private var startDate: Date
    @State private var endDate: Date

    init(
        session: CourseSession? = nil,
        initialCourse: Course? = nil,
        initialWeekday: Weekday = .monday,
        initialStartTimeMinutes: Int = 9 * 60,
        initialEndTimeMinutes: Int? = nil
    ) {
        self.session = session
        let resolvedCourse = session?.course ?? initialCourse
        let semesterRange = SemesterDateRangeStore.load()
        let resolvedRange = resolvedCourse?.effectiveDateRange(semesterRange: semesterRange) ?? semesterRange
        self.initialCourse = resolvedCourse
        _courseID = State(initialValue: resolvedCourse?.id)
        _weekday = State(initialValue: session?.weekday ?? initialWeekday)
        _weekPattern = State(initialValue: session?.weekPattern ?? .all)
        _startTime = State(initialValue: Self.time(for: session?.startTimeMinutes ?? initialStartTimeMinutes))
        _endTime = State(initialValue: Self.time(for: session?.endTimeMinutes ?? initialEndTimeMinutes ?? initialStartTimeMinutes + 110))
        _usesSemesterDateRange = State(initialValue: resolvedCourse?.usesSemesterDateRange ?? true)
        _startDate = State(initialValue: resolvedRange.startDate)
        _endDate = State(initialValue: resolvedRange.endDate)
    }

    var body: some View {
        Form {
            Section("上课安排") {
                if initialCourse == nil {
                    Picker("课程", selection: $courseID) {
                        Text("请选择课程").tag(UUID?.none)
                        ForEach(courses, id: \.id) { course in
                            Text(course.name).tag(UUID?.some(course.id))
                        }
                    }
                }
                Picker("星期", selection: $weekday) { ForEach(Weekday.allCases, id: \.self) { Text("周\(["日","一","二","三","四","五","六"][$0.rawValue - 1])").tag($0) } }
                Picker("周次", selection: $weekPattern) {
                    ForEach(WeekPattern.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                DatePicker("开始时间", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("结束时间", selection: $endTime, displayedComponents: .hourAndMinute)
            }

            Section("课程日期（应用于该课程全部课次）") {
                Toggle("跟随课表学期日期", isOn: $usesSemesterDateRange)
                Text("关闭后可为本课程单独设置起止日期，不影响其他课程。")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
                if usesSemesterDateRange {
                    let range = SemesterDateRangeStore.load()
                    Text("\(localizedDate(range.startDate))–\(localizedDate(range.endDate))")
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                } else {
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
            }
        }.formStyle(.grouped).padding().frame(width: 400)
            .onChange(of: courseID) { _, _ in
                guard initialCourse == nil, let course = selectedCourse else { return }
                let semesterRange = SemesterDateRangeStore.load()
                let effectiveRange = course.effectiveDateRange(semesterRange: semesterRange)
                usesSemesterDateRange = course.usesSemesterDateRange
                startDate = effectiveRange.startDate
                endDate = effectiveRange.endDate
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(selectedCourse == nil || (!usesSemesterDateRange && endDate < startDate)) } }
    }
    private func save() {
        guard let course = selectedCourse else { return }
        let calendar = Calendar.current
        let start = calendar.component(.hour, from: startTime) * 60 + calendar.component(.minute, from: startTime)
        let end = calendar.component(.hour, from: endTime) * 60 + calendar.component(.minute, from: endTime)
        guard start < end else { return }
        let selectedRange = usesSemesterDateRange
            ? SemesterDateRangeStore.load()
            : SemesterDateRange(startDate: startDate, endDate: endDate)
        course.setDateRange(selectedRange, usesSemesterRange: usesSemesterDateRange)
        if let session {
            session.weekday = weekday
            session.startTimeMinutes = start
            session.endTimeMinutes = end
            session.startDate = selectedRange.startDate
            session.endDate = selectedRange.endDate
            session.weekPattern = weekPattern
            session.course = course
        } else {
            modelContext.insert(CourseSession(weekday: weekday, startTimeMinutes: start, endTimeMinutes: end, startDate: selectedRange.startDate, endDate: selectedRange.endDate, weekPattern: weekPattern, course: course))
        }
        try? modelContext.save(); dismiss()
    }

    private var selectedCourse: Course? {
        if let initialCourse { return initialCourse }
        return courses.first(where: { $0.id == courseID })
    }

    private static func time(for minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    private func localizedDate(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day())
    }
}

/// Edits the timetable's left-side class periods without modifying course data.
struct SemesterDateSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var totalWeeks: Int
    let onSave: (SemesterDateRange) -> Void

    init(range: SemesterDateRange, onSave: @escaping (SemesterDateRange) -> Void) {
        _startDate = State(initialValue: range.startDate)
        _endDate = State(initialValue: range.endDate)
        _totalWeeks = State(initialValue: range.weekCount())
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("学期日期") {
                DatePicker("开始日期", selection: startDateBinding, displayedComponents: .date)
                DatePicker("结束日期", selection: endDateBinding, in: startDate..., displayedComponents: .date)
            }

            Section("学期周数") {
                LabeledContent("总周数") {
                    Stepper(value: totalWeeksBinding, in: 1...52) {
                        Text("\(totalWeeks) 周")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("总周数")
                    .fixedSize()
                }

                Label("开始日期所在的自然周为第 1 周，之后每周星期一进入下一周。", systemImage: "calendar.badge.clock")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
        .navigationTitle("学期设置")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    onSave(SemesterDateRange(startDate: startDate, endDate: endDate))
                    dismiss()
                }
                .disabled(endDate < startDate)
            }
        }
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { startDate },
            set: { newValue in
                startDate = newValue
                endDate = SemesterDateRange.endDate(forWeekCount: totalWeeks, startDate: newValue)
            }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { endDate },
            set: { newValue in
                endDate = newValue
                totalWeeks = SemesterDateRange(startDate: startDate, endDate: newValue).weekCount()
            }
        )
    }

    private var totalWeeksBinding: Binding<Int> {
        Binding(
            get: { totalWeeks },
            set: { newValue in
                totalWeeks = min(max(newValue, 1), 52)
                endDate = SemesterDateRange.endDate(forWeekCount: totalWeeks, startDate: startDate)
            }
        )
    }
}

struct TimetablePeriodSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var periods: [TimetablePeriod]
    @State private var draftPeriods: [TimetablePeriod]

    init(periods: Binding<[TimetablePeriod]>) {
        _periods = periods
        _draftPeriods = State(initialValue: periods.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("设置每个节次的名称、开始和结束时间。节次数量即为当天可排课的节次数量。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("课表节次") {
                    ForEach($draftPeriods) { $period in
                        HStack(spacing: 12) {
                            TextField("节次名称", text: $period.name)
                                .frame(width: 90)
                            DatePicker("开始时间", selection: timeBinding(for: $period, keyPath: \.startTimeMinutes), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("至").foregroundStyle(.secondary)
                            DatePicker("结束时间", selection: timeBinding(for: $period, keyPath: \.endTimeMinutes), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Button(role: .destructive) { remove(period.id) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除\(period.name)节次")
                        }
                    }

                    Button(action: addPeriod) {
                        Label("添加节次", systemImage: "plus")
                    }
                }

                if let message = TimetablePeriod.validationMessage(for: draftPeriods) {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()
            HStack {
                Button("恢复默认") { draftPeriods = TimetablePeriod.defaultPeriods }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(TimetablePeriod.validationMessage(for: draftPeriods) != nil)
            }
            .padding()
        }
        .frame(width: 620, height: 560)
    }

    private func addPeriod() {
        let nextNumber = draftPeriods.count + 1
        let latestEnd = draftPeriods.map(\.endTimeMinutes).max() ?? 8 * 60 - 10
        let start = min(latestEnd + 10, 23 * 60)
        let end = min(start + 45, 24 * 60 - 1)
        draftPeriods.append(TimetablePeriod(name: "第 \(nextNumber) 节", startTimeMinutes: start, endTimeMinutes: end))
    }

    private func remove(_ id: UUID) {
        draftPeriods.removeAll { $0.id == id }
    }

    private func save() {
        let sorted = draftPeriods.sorted { $0.startTimeMinutes < $1.startTimeMinutes }
        periods = sorted
        TimetablePeriodStore.save(sorted)
        dismiss()
    }

    private func timeBinding(
        for period: Binding<TimetablePeriod>,
        keyPath: WritableKeyPath<TimetablePeriod, Int>
    ) -> Binding<Date> {
        Binding(
            get: { date(for: period.wrappedValue[keyPath: keyPath]) },
            set: { period.wrappedValue[keyPath: keyPath] = minutes(for: $0) }
        )
    }

    private func date(for minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    private func minutes(for date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}

struct AssignmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: Course
    @State private var title = ""
    @State private var dueDate = Date()
    var body: some View {
        Form { TextField("作业名称", text: $title); DatePicker("截止日期", selection: $dueDate, displayedComponents: .date) }
            .formStyle(.grouped).padding().frame(width: 380)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(title.nilIfEmpty == nil) } }
    }
    private func save() {
        let task = Task(title: title.trimmingCharacters(in: .whitespacesAndNewlines), deadline: dueDate, priority: .medium)
        task.course = course
        let assignment = Assignment(title: task.title, dueDate: dueDate, course: course, linkedTask: task)
        task.assignment = assignment
        modelContext.insert(task); modelContext.insert(assignment); try? modelContext.save(); dismiss()
    }
}

struct ExamEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: Course
    @State private var title = ""
    @State private var date = Date()
    var body: some View {
        Form { TextField("考试名称", text: $title); DatePicker("时间", selection: $date) }.formStyle(.grouped).padding().frame(width: 380)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(title.nilIfEmpty == nil) } }
    }
    private func save() { modelContext.insert(Exam(title: title.trimmingCharacters(in: .whitespacesAndNewlines), startDate: date, course: course)); try? modelContext.save(); dismiss() }
}

// MARK: - Calendar

enum CalendarMode: String, CaseIterable, Identifiable { case month = "月"; case week = "周"; case day = "日"; var id: String { rawValue } }

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigation: AppNavigationCoordinator
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Event.startDate) private var events: [Event]
    @Query(sort: \Task.createdAt) private var tasks: [Task]
    @Query(sort: \Exam.startDate) private var exams: [Exam]
    @Query(sort: \JournalEntry.date, order: .reverse) private var journalEntries: [JournalEntry]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @State private var mode: CalendarMode = .month
    @State private var selectedDate = Date.now
    @State private var isDayInspectorPresented = false
    @State private var isEventEditorPresented = false
    @AppStorage(HabitDisplayConfiguration.storageKey) private var habitDisplaySelection = ""

    var body: some View {
        VStack(spacing: 0) {
            CalendarHeader(
                title: calendarTitle,
                subtitle: mode == .month ? "从日程、日记与习惯回顾这个月" : "按日期查看你的生活安排",
                mode: $mode,
                date: $selectedDate,
                createEvent: { isEventEditorPresented = true }
            )

            GeometryReader { proxy in
                // Keep the primary calendar legible at normal window widths.
                // The selected-day inspector becomes a native sheet before the
                // two panes would compete for space or force horizontal clipping.
                if proxy.size.width >= 980 {
                    HSplitView {
                        calendarContent(presentInspectorOnMonthSelection: false)
                            .frame(minWidth: 620, idealWidth: 760, maxWidth: .infinity, maxHeight: .infinity)

                        dayInspector
                            .frame(minWidth: 260, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)
                    }
                } else {
                    calendarContent(presentInspectorOnMonthSelection: true)
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                isDayInspectorPresented = true
                            } label: {
                                Label("当天生活", systemImage: "sidebar.right")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppColors.accent)
                            .padding(AppSpacing.lg)
                            .accessibilityLabel("查看所选日期的当天生活")
                        }
                }
            }
        }
        .background(AppColors.canvas)
        .sheet(isPresented: $isDayInspectorPresented) {
            dayInspector
                .frame(minWidth: 360, idealWidth: 420, minHeight: 560)
        }
        .sheet(isPresented: $isEventEditorPresented) {
            EventEditor(defaultDate: selectedDate) { createdDate in
                selectedDate = createdDate
            }
        }
        .onAppear {
            if let requestedDate = navigation.takeRequestedCalendarDate() {
                selectedDate = requestedDate
            }
        }
    }

    @ViewBuilder
    private func calendarContent(presentInspectorOnMonthSelection: Bool) -> some View {
        switch mode {
        case .month:
            CalendarMonthContent(
                date: $selectedDate,
                journalEntries: journalEntries,
                habits: displayedHabits,
                courses: courses,
                events: events,
                tasks: tasks,
                exams: exams,
                onDateSelected: {
                    if presentInspectorOnMonthSelection {
                        isDayInspectorPresented = true
                    }
                }
            )
        case .week:
            WeekCalendarView(date: $selectedDate, courses: courses, events: events, tasks: tasks, exams: exams)
        case .day:
            DayCalendarView(date: selectedDate, courses: courses, events: events, tasks: tasks, exams: exams)
        }
    }

    private func openJournal() {
        _ = JournalEntryService.ensureEntry(for: selectedDate, in: journalEntries, modelContext: modelContext)
        navigation.showJournal(on: selectedDate)
    }

    private var calendarTitle: String {
        selectedDate.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide))
    }

    private var displayedHabits: [Habit] {
        HabitDisplayConfiguration.visibleHabits(from: habits, selection: habitDisplaySelection)
    }

    private var dayInspector: some View {
        CalendarDayInspector(
            date: selectedDate,
            journalEntries: journalEntries,
            habits: displayedHabits,
            courses: courses,
            events: events,
            tasks: tasks,
            exams: exams,
            openJournal: openJournal,
            openTasks: navigation.showTasks
        )
    }
}

/// Keeps the calendar controls readable when the content area is narrower than
/// a full title-and-toolbar row. `ViewThatFits` prefers the single-line macOS
/// toolbar but falls back to a deliberate two-row layout instead of clipping.
private struct CalendarHeader: View {
    let title: String
    let subtitle: String
    @Binding var mode: CalendarMode
    @Binding var date: Date
    let createEvent: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: AppSpacing.lg) {
                headerText
                Spacer(minLength: AppSpacing.md)
                controls
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                headerText
                controls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.xl)
        .padding(.bottom, AppSpacing.lg)
    }

    private var headerText: some View {
        LifePageHeader(eyebrow: nil, title: title, subtitle: subtitle)
    }

    private var controls: some View {
        HStack(spacing: AppSpacing.sm) {
            Picker("视图", selection: $mode) {
                ForEach(CalendarMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 162)

            Button("今天") { date = .now }
                .buttonStyle(.bordered)
                .tint(AppColors.accent)

            Button(action: createEvent) {
                Label("新建日程", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.bordered)
            .tint(AppColors.calendar)
            .accessibilityLabel("新建日程")

            DatePicker("日期", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .frame(width: 132)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Creates one local Event from the Calendar surface. Events are immediately
/// read by the existing Today, Calendar, and Journal aggregation services.
private struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let onSaved: (Date) -> Void

    @State private var title = ""
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isAllDay = false
    @State private var location = ""
    @State private var eventDescription = ""

    init(defaultDate: Date, onSaved: @escaping (Date) -> Void) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: defaultDate)
        let defaultStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let defaultEnd = calendar.date(byAdding: .hour, value: 1, to: defaultStart) ?? defaultStart

        self.onSaved = onSaved
        _date = State(initialValue: day)
        _startTime = State(initialValue: defaultStart)
        _endTime = State(initialValue: defaultEnd)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("日程") {
                    TextField("标题", text: $title)
                    TextField("地点（可选）", text: $location)
                }

                Section("时间") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Toggle("全天", isOn: $isAllDay)
                    if !isAllDay {
                        DatePicker("开始时间", selection: $startTime, displayedComponents: .hourAndMinute)
                        DatePicker("结束时间", selection: $endTime, displayedComponents: .hourAndMinute)
                        if endDate <= startDate {
                            Text("结束时间需要晚于开始时间。")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.deadline)
                        }
                    }
                }

                Section("备注") {
                    TextEditor(text: $eventDescription)
                        .font(AppTypography.body)
                        .frame(minHeight: 88)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.nilIfEmpty == nil || (!isAllDay && endDate <= startDate))
            }
            .padding(AppSpacing.lg)
        }
        .frame(minWidth: 440, idealWidth: 480, minHeight: 460, idealHeight: 520)
        .accessibilityLabel("新建日程")
    }

    private var startDate: Date {
        combinedDate(with: startTime)
    }

    private var endDate: Date {
        combinedDate(with: endTime)
    }

    private func combinedDate(with time: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(from: DateComponents(
            year: day.year,
            month: day.month,
            day: day.day,
            hour: clock.hour,
            minute: clock.minute
        )) ?? date
    }

    private func save() {
        let event = Event(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: isAllDay ? Calendar.current.startOfDay(for: date) : startDate,
            endDate: isAllDay ? nil : endDate,
            isAllDay: isAllDay,
            eventType: .personal,
            eventDescription: eventDescription.nilIfEmpty,
            location: location.nilIfEmpty
        )
        modelContext.insert(event)
        try? modelContext.save()
        onSaved(event.startDate)
        dismiss()
    }
}

struct DayCalendarView: View {
    let date: Date; let courses: [Course]; let events: [Event]; let tasks: [Task]; let exams: [Exam]
    var body: some View {
        let items = ScheduleAggregationService.items(for: date, courses: courses, events: events, tasks: tasks, exams: exams)
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                LifeSectionHeader(date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month(.wide).day().weekday(.wide)), subtitle: "当天安排")
                LifeSurface {
                    if items.isEmpty {
                        EmptyInlineView(text: "当天没有带具体时间的安排。")
                    } else {
                        TimelineList(items: items)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.bottom, AppSpacing.page)
        }
    }
}

struct WeekCalendarView: View {
    @Binding var date: Date; let courses: [Course]; let events: [Event]; let tasks: [Task]; let exams: [Exam]

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date

        GeometryReader { proxy in
            let columnWidth = max(168, (proxy.size.width - 64) / 7)

            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 12) {
                    weekColumn(offset: 0, calendar: calendar, start: start, width: columnWidth, height: proxy.size.height)
                    weekColumn(offset: 1, calendar: calendar, start: start, width: columnWidth, height: proxy.size.height)
                    weekColumn(offset: 2, calendar: calendar, start: start, width: columnWidth, height: proxy.size.height)
                    weekColumn(offset: 3, calendar: calendar, start: start, width: columnWidth, height: proxy.size.height)
                    weekColumn(offset: 4, calendar: calendar, start: start, width: columnWidth, height: proxy.size.height)
                    weekColumn(offset: 5, calendar: calendar, start: start, width: columnWidth, height: proxy.size.height)
                    weekColumn(offset: 6, calendar: calendar, start: start, width: columnWidth, height: proxy.size.height)
                }
                .padding(AppSpacing.page)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        }
    }

    private func weekColumn(offset: Int, calendar: Calendar, start: Date, width: CGFloat, height: CGFloat) -> some View {
        let day = calendar.date(byAdding: .day, value: offset, to: start) ?? date
        let items = ScheduleAggregationService.items(for: day, courses: courses, events: events, tasks: tasks, exams: exams)

        return WeekCalendarDayColumn(
            date: day,
            items: items,
            isToday: calendar.isDateInToday(day),
            isSelected: calendar.isDate(day, inSameDayAs: date),
            onSelect: { date = day }
        )
        .frame(width: width, height: max(420, height - 40), alignment: .top)
    }
}

/// A focused day column for the weekly calendar. It keeps the schedule at the
/// top of the page, while category icons and tints make mixed sources scannable.
private struct WeekCalendarDayColumn: View {
    let date: Date
    let items: [ScheduleItem]
    let isToday: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(weekdayTitle)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColors.primaryText)
                        Text(date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day()))
                            .font(AppTypography.caption)
                            .foregroundStyle(isToday ? AppColors.accent : AppColors.secondaryText)
                    }

                    Spacer(minLength: 0)

                    if isToday {
                        Text("今天")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.surface)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppColors.accent, in: Capsule())
                    }
                }
                .padding(AppSpacing.sm)
                .background(headerBackground, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)

            if items.isEmpty {
                Text("没有安排")
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
            } else {
                ForEach(items, id: \.id) { item in
                    WeekCalendarItemCard(item: item)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.sm)
        .background(AppColors.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppColors.surfaceBorder, lineWidth: 1)
        }
    }

    private var weekdayTitle: String {
        ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][calendar.component(.weekday, from: date) - 1]
    }

    private var headerBackground: Color {
        if isToday { return AppColors.accent.opacity(0.13) }
        if isSelected { return AppColors.primaryText.opacity(0.07) }
        return .clear
    }
}

private struct WeekCalendarItemCard: View {
    let item: ScheduleItem

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            Image(systemName: item.category.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 14, alignment: .center)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(item.startDate, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppColors.secondaryText)
                Text(item.title)
                    .font(AppTypography.caption.weight(.medium))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 5)
        }
    }

    private var tint: Color {
        switch item.category {
        case .course:
            color(from: item.colorHex)
        case .event:
            AppColors.calendar
        case .task:
            AppColors.task
        case .exam:
            AppColors.deadline
        }
    }

    /// Course colors are stored as portable hex strings; invalid legacy values
    /// fall back to the muted course token rather than affecting the layout.
    private func color(from hex: String?) -> Color {
        guard let hex else { return AppColors.course }
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return AppColors.course }

        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// Gives the main month grid a persistent date navigator when the available
/// width permits it. Both representations operate on the same selected date.
private struct CalendarMonthContent: View {
    @Binding var date: Date
    let journalEntries: [JournalEntry]
    let habits: [Habit]
    let courses: [Course]
    let events: [Event]
    let tasks: [Task]
    let exams: [Exam]
    let onDateSelected: () -> Void

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 620 {
                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    MiniMonthCalendarNavigator(date: $date)
                        .frame(width: 160)
                        .padding(.leading, AppSpacing.page)

                    MonthCalendarGrid(
                        date: $date,
                        journalEntries: journalEntries,
                        habits: habits,
                        courses: courses,
                        events: events,
                        tasks: tasks,
                        exams: exams,
                        onDateSelected: onDateSelected
                    )
                }
            } else {
                MonthCalendarGrid(
                    date: $date,
                    journalEntries: journalEntries,
                    habits: habits,
                    courses: courses,
                    events: events,
                    tasks: tasks,
                    exams: exams,
                    onDateSelected: onDateSelected
                )
            }
        }
    }
}

/// Shared six-week month geometry keeps the main grid and the navigator
/// perfectly aligned, including their Sunday/Monday start configuration.
enum MonthCalendarLayout {
    static func visibleDays(for date: Date, calendar: Calendar = .current) -> [Date] {
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let weekdayOffset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: monthStart) ?? monthStart

        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let firstIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }
}

/// A compact, always-visible-in-normal-widths date picker for the month view.
/// It intentionally uses native buttons rather than a second persisted state.
private struct MiniMonthCalendarNavigator: View {
    @Binding var date: Date
    private let calendar = Calendar.current

    var body: some View {
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let visibleDays = MonthCalendarLayout.visibleDays(for: date, calendar: calendar)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: AppSpacing.xxs), count: 7)

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Button(action: { moveMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一月")

                Text(monthStart.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide)))
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)

                Button(action: { moveMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一月")
            }
            .foregroundStyle(AppColors.secondaryText)

            LazyVGrid(columns: columns, spacing: AppSpacing.xxs) {
                ForEach(MonthCalendarLayout.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity)
                }

                ForEach(visibleDays, id: \.self) { day in
                    Button {
                        date = day
                    } label: {
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 10, weight: calendar.isDate(day, inSameDayAs: date) ? .bold : .regular, design: .rounded))
                            .foregroundStyle(dayColor(for: day, monthStart: monthStart))
                            .frame(maxWidth: .infinity, minHeight: 18)
                            .background(selectionBackground(for: day), in: Circle())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day().weekday(.wide)))
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(AppColors.surface.opacity(0.56), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                .stroke(AppColors.surfaceBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("日期导航")
    }

    private func moveMonth(by value: Int) {
        date = calendar.date(byAdding: .month, value: value, to: date) ?? date
    }

    private func dayColor(for day: Date, monthStart: Date) -> Color {
        if calendar.isDate(day, inSameDayAs: date) { return AppColors.surface }
        if !calendar.isDate(day, equalTo: monthStart, toGranularity: .month) { return AppColors.secondaryText.opacity(0.45) }
        if calendar.isDateInToday(day) { return AppColors.accent }
        return AppColors.primaryText
    }

    private func selectionBackground(for day: Date) -> Color {
        calendar.isDate(day, inSameDayAs: date) ? AppColors.accent : .clear
    }
}

/// Quiet monthly overview: a date is a life-status summary rather than a
/// miniature agenda. Detailed items remain available from the day inspector.
struct MonthCalendarGrid: View {
    @Binding var date: Date
    let journalEntries: [JournalEntry]
    let habits: [Habit]
    let courses: [Course]
    let events: [Event]
    let tasks: [Task]
    let exams: [Exam]
    let onDateSelected: () -> Void

    var body: some View {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let visibleDays = MonthCalendarLayout.visibleDays(for: date, calendar: calendar)
        let weekdaySymbols = MonthCalendarLayout.weekdaySymbols(calendar: calendar)

        GeometryReader { proxy in
            // A six-row grid keeps the month stable as the selected month
            // changes. The row height is derived from the real remaining area,
            // so a normal macOS window shows the entire month without scrolling.
            let horizontalInset = AppSpacing.page * 2
            let verticalInset = AppSpacing.md * 2
            let headerHeight: CGFloat = 20
            let rowSpacing = AppSpacing.xxs
            let contentHeight = max(0, proxy.size.height - verticalInset - headerHeight - rowSpacing * 6)
            let rowHeight = max(62, contentHeight / 6)
            let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: rowSpacing), count: 7)

            ScrollView(.vertical) {
                VStack(spacing: AppSpacing.xs) {
                    LazyVGrid(columns: columns, spacing: rowSpacing) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(AppTypography.caption.weight(.semibold))
                                .foregroundStyle(AppColors.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: headerHeight)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: rowSpacing) {
                        ForEach(visibleDays, id: \.self) { day in
                            let overview = DailyLifeOverviewService.overview(
                                for: day,
                                journalEntries: journalEntries,
                                habits: habits,
                                courses: courses,
                                events: events,
                                tasks: tasks,
                                exams: exams,
                                calendar: calendar
                            )
                            MonthCalendarDayCell(
                                day: day,
                                overview: overview,
                                isInDisplayedMonth: calendar.isDate(day, equalTo: monthStart, toGranularity: .month),
                                isToday: calendar.isDateInToday(day),
                                isSelected: calendar.isDate(day, inSameDayAs: date),
                                height: rowHeight,
                                select: {
                                    date = day
                                    onDateSelected()
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.md)
                .frame(minWidth: max(0, proxy.size.width - horizontalInset), minHeight: proxy.size.height, alignment: .top)
            }
            .background(AppColors.surface.opacity(0.3), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                    .stroke(AppColors.surfaceBorder, lineWidth: 1)
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.bottom, AppSpacing.page)
        }
    }

}

private struct MonthCalendarDayCell: View {
    let day: Date
    let overview: DailyLifeOverview
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let height: CGFloat
    let select: () -> Void

    private var dayNumber: Int {
        Calendar.current.component(.day, from: day)
    }

    /// The grid uses each habit's existing symbol so the month remains a
    /// compact, recognisable life map without introducing duplicate labels.
    private var completedHabitStatuses: [DailyHabitStatus] {
        overview.habitStatuses.filter(\.isCompleted)
    }

    private var visibleCompletedHabitStatuses: [DailyHabitStatus] {
        Array(completedHabitStatuses.prefix(4))
    }

    private var hiddenCompletedHabitCount: Int {
        max(0, completedHabitStatuses.count - visibleCompletedHabitStatuses.count)
    }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(dayNumber)")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(dayNumberColor)
                    Spacer(minLength: 0)
                    if isInDisplayedMonth && overview.hasJournal {
                        Image(systemName: "square.and.pencil")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.journal)
                            .help("已记录日记")
                            .accessibilityLabel("已记录日记")
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 3) {
                    if isInDisplayedMonth && !visibleCompletedHabitStatuses.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(visibleCompletedHabitStatuses) { status in
                                Image(systemName: status.habit.symbolName)
                                    .font(.system(size: 10, weight: .medium))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(AppColors.accent)
                                    .frame(width: 12, height: 12)
                                    .help("已完成习惯：\(status.habit.name)")
                                    .accessibilityLabel("已完成习惯：\(status.habit.name)")
                            }
                            if hiddenCompletedHabitCount > 0 {
                                Text("+\(hiddenCompletedHabitCount)")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppColors.secondaryText)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .accessibilityLabel("另有 \(hiddenCompletedHabitCount) 个已完成习惯")
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(completedHabitAccessibilityLabel)
                    }

                    HStack(spacing: AppSpacing.xs) {
                        // An empty day stays intentionally quiet. When progress
                        // exists, the fixed-size signals never wrap or carry
                        // titles that would turn a month into a cramped agenda.
                        if isInDisplayedMonth && overview.totalHabitCount > 0 && overview.completedHabitCount > 0 {
                            HabitCompletionRing(
                                completed: overview.completedHabitCount,
                                total: overview.totalHabitCount,
                                size: 15
                            )
                            .help(overview.habitTooltip)
                        }
                        if isInDisplayedMonth && !overview.dailyTasks.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle")
                                Text("\(overview.completedTasks.count)/\(overview.dailyTasks.count)")
                                    .monospacedDigit()
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AppColors.secondaryText)
                                .accessibilityLabel("任务完成 \(overview.completedTasks.count) / \(overview.dailyTasks.count)")
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .contentShape(Rectangle())
            .background(background)
            .overlay {
                Rectangle()
                    .stroke(isSelected ? AppColors.accent.opacity(0.55) : AppColors.surfaceBorder.opacity(0.8), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help(cellTooltip)
        .accessibilityLabel(cellTooltip)
    }

    private var background: Color {
        if isSelected { return AppColors.accent.opacity(0.14) }
        if isToday { return AppColors.calendar.opacity(0.11) }
        return .clear
    }

    private var dayNumberColor: Color {
        if !isInDisplayedMonth { return AppColors.secondaryText.opacity(0.5) }
        if isToday { return AppColors.accent }
        return AppColors.primaryText
    }

    private var cellTooltip: String {
        var details = [day.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day())]
        if overview.hasJournal { details.append("已记录日记") }
        if overview.totalHabitCount > 0 { details.append("习惯 \(overview.completedHabitCount) / \(overview.totalHabitCount) 完成") }
        if !overview.dailyTasks.isEmpty { details.append("任务 \(overview.completedTasks.count) / \(overview.dailyTasks.count) 完成") }
        return details.joined(separator: " · ")
    }

    private var completedHabitAccessibilityLabel: String {
        "已完成习惯：" + completedHabitStatuses.map { $0.habit.name }.joined(separator: "、")
    }
}

private struct HabitCompletionRing: View {
    let completed: Int
    let total: Int
    let size: CGFloat

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.divider.opacity(0.75), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("习惯完成 \(completed) / \(total)")
    }
}

private struct CalendarDayInspector: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(HabitDisplayConfiguration.storageKey) private var habitDisplaySelection = ""
    let date: Date
    let journalEntries: [JournalEntry]
    let habits: [Habit]
    let courses: [Course]
    let events: [Event]
    let tasks: [Task]
    let exams: [Exam]
    let openJournal: () -> Void
    let openTasks: () -> Void
    @State private var isHabitManagerPresented = false
    @State private var trackedHabit: Habit?

    var body: some View {
        let overview = DailyLifeOverviewService.overview(
            for: date,
            journalEntries: journalEntries,
            habits: habits,
            courses: courses,
            events: events,
            tasks: tasks,
            exams: exams
        )

        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month(.wide).day().weekday(.wide)))
                        .font(AppTypography.editorialDate)
                        .foregroundStyle(AppColors.primaryText)
                    Text("当天生活")
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                }

                journalCard(overview)
                scheduleSection(overview)
                habitSection(overview)
                taskSection(overview)
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.sidebar.opacity(0.62))
        .sheet(isPresented: $isHabitManagerPresented) {
            HabitManagementSheet(selection: $habitDisplaySelection)
        }
        .sheet(item: $trackedHabit) { habit in
            HabitHistorySheet(habit: habit)
        }
    }

    @ViewBuilder
    private func journalCard(_ overview: DailyLifeOverview) -> some View {
        LifeSurface(padding: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label(overview.hasJournal ? "已记录日记" : "今天还没有记录", systemImage: overview.hasJournal ? "square.and.pencil" : "book.closed")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.primaryText)
                if let preview = overview.journalPreview {
                    Text(preview)
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(3)
                } else {
                    Text("从一句话开始，留下一点属于这一天的记忆。")
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                }
                Button(overview.hasJournal ? "查看日记" : "写日记", action: openJournal)
                    .buttonStyle(.bordered)
                    .tint(AppColors.accent)
                    .accessibilityLabel(overview.hasJournal ? "查看当天日记" : "为当天写日记")
            }
        }
    }

    @ViewBuilder
    private func scheduleSection(_ overview: DailyLifeOverview) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            LifeSectionHeader("今日安排", subtitle: "\(overview.scheduleItems.count) 项")
            if overview.scheduleItems.isEmpty {
                EmptyInlineView(text: "当天没有带具体时间的安排。")
            } else {
                LifeSurface(padding: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(overview.scheduleItems, id: \.id) { item in
                            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                                Text(item.startDate, format: .dateTime.hour().minute())
                                    .font(AppTypography.timelineTime)
                                    .foregroundStyle(AppColors.secondaryText)
                                Image(systemName: item.category.symbolName)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.calendar)
                                Text(item.title)
                                    .font(AppTypography.metadata.weight(.medium))
                                    .foregroundStyle(AppColors.primaryText)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func habitSection(_ overview: DailyLifeOverview) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("今日习惯")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.primaryText)
                    Text(overview.totalHabitCount == 0 ? "尚未添加" : "\(overview.completedHabitCount) / \(overview.totalHabitCount) 完成")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }
                Spacer(minLength: 0)
                Button {
                    isHabitManagerPresented = true
                } label: {
                    Label("管理", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .tint(AppColors.accent)
                .accessibilityLabel("管理展示的今日习惯")
            }
            if overview.habitStatuses.isEmpty {
                EmptyInlineView(text: "还没有展示的习惯。点击“管理”添加或选择习惯。")
            } else {
                LifeSurface(padding: AppSpacing.md) {
                    VStack(spacing: AppSpacing.xs) {
                        ForEach(overview.habitStatuses) { status in
                            HabitStatusRow(
                                status: status,
                                toggle: {
                                    HabitService.toggle(status.habit, on: date, in: modelContext)
                                },
                                openHistory: {
                                    trackedHabit = status.habit
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func taskSection(_ overview: DailyLifeOverview) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                LifeSectionHeader("今日任务", subtitle: overview.dailyTasks.isEmpty ? "没有任务" : "完成 \(overview.completedTasks.count) / \(overview.dailyTasks.count)")
                Button("查看任务", action: openTasks)
                    .buttonStyle(.plain)
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
                    .accessibilityLabel("前往任务页面")
            }
            if overview.dailyTasks.isEmpty {
                EmptyInlineView(text: "当天没有任务记录。")
            } else {
                LifeSurface(padding: AppSpacing.md) {
                    VStack(spacing: AppSpacing.xs) {
                        ForEach(overview.dailyTasks, id: \.id) { task in
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.status == .completed ? AppColors.accent : AppColors.secondaryText)
                                Text(task.title)
                                    .font(AppTypography.metadata)
                                    .foregroundStyle(AppColors.primaryText)
                                    .strikethrough(task.status == .completed, color: AppColors.secondaryText)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HabitStatusRow: View {
    let status: DailyHabitStatus
    let toggle: () -> Void
    let openHistory: (() -> Void)?

    init(
        status: DailyHabitStatus,
        toggle: @escaping () -> Void,
        openHistory: (() -> Void)? = nil
    ) {
        self.status = status
        self.toggle = toggle
        self.openHistory = openHistory
    }

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Button(action: toggle) {
                Image(systemName: status.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(status.isCompleted ? AppColors.accent : AppColors.secondaryText)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(status.habit.name)，\(status.isCompleted ? "已完成，点按取消" : "待完成，点按完成")")

            if let openHistory {
                Button(action: openHistory) {
                    habitLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(status.habit.name)的完成轨迹")
                .help("查看完成轨迹")
            } else {
                habitLabel
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(status.habit.name)，\(status.isCompleted ? "已完成" : "待完成")")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var habitLabel: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: status.habit.symbolName)
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 16)
            Text(status.habit.name)
                .font(AppTypography.metadata)
                .foregroundStyle(AppColors.primaryText)
            Spacer(minLength: 0)
            Text(status.isCompleted ? "已完成" : "待完成")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
            if openHistory != nil {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(AppColors.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A focused, editable history calendar for one habit. It reads and writes the
/// existing HabitRecord relationship, so a completion changed here is reflected
/// immediately by Calendar, Journal and Today without creating a new summary.
private struct HabitHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let habit: Habit

    @State private var mode: HabitHistoryMode = .month
    @State private var displayedDate = Date.now

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("视图", selection: $mode) {
                ForEach(HabitHistoryMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
            .padding(.top, AppSpacing.md)

            Group {
                switch mode {
                case .month:
                    HabitHistoryMonthGrid(
                        habit: habit,
                        month: displayedDate,
                        toggleCompletion: toggleCompletion
                    )
                case .year:
                    HabitHistoryYearGrid(
                        habit: habit,
                        year: displayedDate,
                        selectMonth: { selectedMonth in
                            displayedDate = selectedMonth
                            mode = .month
                        }
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)

            statistics
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 620, idealHeight: 720)
        .background(AppColors.canvas)
    }

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: habit.symbolName)
                .font(.title3)
                .foregroundStyle(AppColors.accent)
                .frame(width: 28, height: 28)
                .background(AppColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(habit.name)
                    .font(AppTypography.editorialDate)
                    .foregroundStyle(AppColors.primaryText)
                Text(mode == .month ? "完成轨迹 · 点按日期补记或撤销" : "全年完成轨迹")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: AppSpacing.sm)

            Button {
                moveDisplayedDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(mode == .month ? "上个月" : "上一年")

            Text(navigationTitle)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.primaryText)
                .frame(minWidth: mode == .month ? 132 : 76)
                .monospacedDigit()

            Button {
                moveDisplayedDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(mode == .month ? "下个月" : "下一年")

            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
        }
        .padding(AppSpacing.lg)
    }

    private var statistics: some View {
        HStack(spacing: AppSpacing.sm) {
            HabitHistoryMetric(
                title: mode == .month ? "本月完成" : "本年完成",
                value: "\(mode == .month ? HabitHistoryService.completionCount(for: habit, inMonthContaining: displayedDate, calendar: calendar) : HabitHistoryService.completionCount(for: habit, inYearContaining: displayedDate, calendar: calendar)) 次",
                symbolName: "checkmark.circle"
            )
            HabitHistoryMetric(
                title: "当前连续",
                value: "\(HabitHistoryService.currentStreak(for: habit, calendar: calendar)) 天",
                symbolName: "flame"
            )
            HabitHistoryMetric(
                title: "最长连续",
                value: "\(HabitHistoryService.longestStreak(for: habit, calendar: calendar)) 天",
                symbolName: "trophy"
            )
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .month:
            displayedDate.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide))
        case .year:
            displayedDate.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year())
        }
    }

    private func moveDisplayedDate(by value: Int) {
        let component: Calendar.Component = mode == .month ? .month : .year
        displayedDate = calendar.date(byAdding: component, value: value, to: displayedDate) ?? displayedDate
    }

    private func toggleCompletion(on date: Date) {
        HabitService.toggle(habit, on: date, in: modelContext, calendar: calendar)
    }
}

private enum HabitHistoryMode: String, CaseIterable, Identifiable {
    case month = "月"
    case year = "年"

    var id: String { rawValue }
}

private struct HabitHistoryMonthGrid: View {
    let habit: Habit
    let month: Date
    let toggleCompletion: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let weekdayOffset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: monthStart) ?? monthStart
        let days = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: AppSpacing.xs), count: 7)

        VStack(spacing: AppSpacing.xs) {
            LazyVGrid(columns: columns, spacing: AppSpacing.xs) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }

            LazyVGrid(columns: columns, spacing: AppSpacing.xs) {
                ForEach(days, id: \.self) { day in
                    HabitHistoryDayCell(
                        day: day,
                        isInDisplayedMonth: calendar.isDate(day, equalTo: monthStart, toGranularity: .month),
                        isCompleted: HabitHistoryService.isCompleted(habit, on: day, calendar: calendar),
                        isFuture: day > calendar.startOfDay(for: .now),
                        toggleCompletion: { toggleCompletion(day) }
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(month.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide)))的\(habit.name)完成日历")
    }

    private var weekdaySymbols: [String] {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let firstIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }
}

private struct HabitHistoryDayCell: View {
    let day: Date
    let isInDisplayedMonth: Bool
    let isCompleted: Bool
    let isFuture: Bool
    let toggleCompletion: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: toggleCompletion) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("\(calendar.component(.day, from: day))")
                    .font(AppTypography.metadata.weight(.medium))
                    .foregroundStyle(dayNumberColor)
                Spacer(minLength: 0)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.surface)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(AppSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .topLeading)
            .background(background, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(isCompleted ? AppColors.accent.opacity(0.9) : AppColors.surfaceBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isInDisplayedMonth || isFuture)
        .opacity(isInDisplayedMonth ? (isFuture ? 0.48 : 1) : 0.35)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private var background: Color {
        if isCompleted { return AppColors.accent.opacity(0.7) }
        if isFuture { return AppColors.sidebar.opacity(0.55) }
        return AppColors.surface
    }

    private var dayNumberColor: Color {
        isCompleted ? AppColors.surface : AppColors.primaryText
    }

    private var accessibilityLabel: String {
        let formattedDate = day.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day().weekday(.wide))
        if !isInDisplayedMonth { return "\(formattedDate)，不在当前月份" }
        if isFuture { return "\(formattedDate)，未来日期" }
        return "\(formattedDate)，\(isCompleted ? "已完成，点按撤销" : "未完成，点按补记")"
    }
}

private struct HabitHistoryYearGrid: View {
    let habit: Habit
    let year: Date
    let selectMonth: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        let yearStart = calendar.dateInterval(of: .year, for: year)?.start ?? year
        let months = (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: yearStart) }
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: AppSpacing.md), count: 3)

        ScrollView {
            LazyVGrid(columns: columns, spacing: AppSpacing.md) {
                ForEach(months, id: \.self) { month in
                    HabitHistoryMiniMonth(
                        habit: habit,
                        month: month,
                        selectMonth: { selectMonth(month) }
                    )
                }
            }
            .padding(.bottom, AppSpacing.xs)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct HabitHistoryMiniMonth: View {
    let habit: Habit
    let month: Date
    let selectMonth: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let weekdayOffset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let numberOfDays = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 3), count: 7)

        Button(action: selectMonth) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(month.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month(.wide)))
                    .font(AppTypography.metadata.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)

                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(0..<weekdayOffset, id: \.self) { _ in
                        Color.clear.frame(height: 10)
                    }
                    ForEach(1...numberOfDays, id: \.self) { dayNumber in
                        let day = calendar.date(byAdding: .day, value: dayNumber - 1, to: monthStart) ?? monthStart
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(HabitHistoryService.isCompleted(habit, on: day, calendar: calendar) ? AppColors.accent : AppColors.divider.opacity(0.55))
                            .frame(height: 10)
                            .help("\(day.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day()))\(HabitHistoryService.isCompleted(habit, on: day, calendar: calendar) ? "已完成" : "未完成")")
                    }
                }
            }
            .padding(AppSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(AppColors.surfaceBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看\(month.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide)))的完成日历")
    }
}

private struct HabitHistoryMetric: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(AppTypography.bodyEmphasis.monospacedDigit())
                    .foregroundStyle(AppColors.primaryText)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(AppColors.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.sidebar.opacity(0.72), in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }
}

/// A small, local configuration surface for the habit list shared by Calendar
/// and Journal. It never edits historical HabitRecord data.
private struct HabitManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Binding var selection: String

    @State private var customHabitName = ""
    @State private var customSymbolName = "sparkles"

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                LifePageHeader(
                    eyebrow: nil,
                    title: "管理今日习惯",
                    subtitle: "选择后会同步显示在日历与日记中"
                )
                Spacer(minLength: 0)
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(AppSpacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    displayedHabitSection
                    presetSection
                    customHabitSection
                }
                .padding(AppSpacing.lg)
            }
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 520, idealHeight: 620)
        .accessibilityLabel("管理展示的今日习惯")
    }

    @ViewBuilder
    private var displayedHabitSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            managementSectionHeader("展示中的习惯", subtitle: "移除后会同时从日历和日记隐藏")
            if visibleHabits.isEmpty {
                EmptyInlineView(text: "还没有展示的习惯。可从下方常用习惯中选择，或添加自定义习惯。")
            } else {
                LifeSurface(padding: AppSpacing.md) {
                    VStack(spacing: AppSpacing.xs) {
                        ForEach(visibleHabits) { habit in
                            selectedHabitRow(habit)
                        }
                    }
                }
            }
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            managementSectionHeader("常用习惯", subtitle: "点按即可添加或重新展示")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 126), spacing: AppSpacing.sm)],
                alignment: .leading,
                spacing: AppSpacing.sm
            ) {
                ForEach(HabitPreset.common) { preset in
                    presetButton(preset)
                }
            }
        }
    }

    private var customHabitSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            managementSectionHeader("自定义习惯", subtitle: "可自定义名称与图标")
            LifeSurface(padding: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        TextField("例如：整理桌面", text: $customHabitName)
                            .textFieldStyle(.roundedBorder)
                        Picker("图标", selection: $customSymbolName) {
                            ForEach(HabitPreset.symbolOptions) { option in
                                Label(option.name, systemImage: option.symbolName)
                                    .tag(option.symbolName)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 116)
                    }

                    HStack {
                        Image(systemName: customSymbolName)
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 16)
                        Text("\(customHabitName.nilIfEmpty ?? "自定义习惯")")
                            .font(AppTypography.metadata)
                            .foregroundStyle(customHabitName.nilIfEmpty == nil ? AppColors.secondaryText : AppColors.primaryText)
                        Spacer(minLength: 0)
                        Button("添加", action: addCustomHabit)
                            .buttonStyle(.bordered)
                            .tint(AppColors.accent)
                            .disabled(customHabitName.nilIfEmpty == nil)
                    }
                }
            }
        }
    }

    private func presetButton(_ preset: HabitPreset) -> some View {
        let existing = matchingHabit(named: preset.name)
        let isAlreadyVisible = existing.map(isVisible) ?? false

        return Button {
            addOrEnableHabit(named: preset.name, symbolName: preset.symbolName)
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: preset.symbolName)
                    .frame(width: 15)
                Text(preset.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: isAlreadyVisible ? "checkmark.circle.fill" : "plus.circle")
            }
            .font(AppTypography.caption.weight(.medium))
            .foregroundStyle(isAlreadyVisible ? AppColors.accent : AppColors.primaryText)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.sm)
            .background(
                isAlreadyVisible ? AppColors.accent.opacity(0.14) : AppColors.surface,
                in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                    .stroke(AppColors.surfaceBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isAlreadyVisible ? "已展示" : "添加")习惯：\(preset.name)")
    }

    private func selectedHabitRow(_ habit: Habit) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: habit.symbolName)
                .foregroundStyle(AppColors.accent)
                .frame(width: 20, alignment: .center)

            Text(habit.name)
                .font(AppTypography.metadata)
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                removeFromDisplay(habit)
            } label: {
                Label("移除", systemImage: "minus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(AppColors.deadline)
            .accessibilityLabel("从日历和日记中移除习惯：\(habit.name)")
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
    }

    private func managementSectionHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.primaryText)
            Text(subtitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibleHabits: [Habit] {
        habits.filter(isVisible)
    }

    private func removeFromDisplay(_ habit: Habit) {
        selection = HabitDisplayConfiguration.updating(
            selection: selection,
            habit: habit,
            isVisible: false,
            among: habits
        )
    }

    private func isVisible(_ habit: Habit) -> Bool {
        HabitDisplayConfiguration.isVisible(habit, selection: selection)
    }

    private func matchingHabit(named name: String) -> Habit? {
        habits.first { habit in
            habit.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: .current) == .orderedSame
        }
    }

    private func addCustomHabit() {
        guard let name = customHabitName.nilIfEmpty else { return }
        addOrEnableHabit(named: name, symbolName: customSymbolName)
        customHabitName = ""
        customSymbolName = "sparkles"
    }

    private func addOrEnableHabit(named name: String, symbolName: String) {
        if let existing = matchingHabit(named: name) {
            selection = HabitDisplayConfiguration.updating(
                selection: selection,
                habit: existing,
                isVisible: true,
                among: habits
            )
            return
        }

        let habit = Habit(name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbolName: symbolName)
        modelContext.insert(habit)
        try? modelContext.save()
        selection = HabitDisplayConfiguration.updating(
            selection: selection,
            habit: habit,
            isVisible: true,
            among: habits + [habit]
        )
    }
}

private struct HabitPreset: Identifiable {
    let name: String
    let symbolName: String

    var id: String { name }

    static let common: [HabitPreset] = [
        HabitPreset(name: "阅读", symbolName: "book.closed"),
        HabitPreset(name: "背英语", symbolName: "character"),
        HabitPreset(name: "运动", symbolName: "figure.run"),
        HabitPreset(name: "喝水", symbolName: "drop.fill"),
        HabitPreset(name: "早睡", symbolName: "bed.double.fill"),
        HabitPreset(name: "冥想", symbolName: "sparkles"),
        HabitPreset(name: "写日记", symbolName: "square.and.pencil"),
        HabitPreset(name: "拉伸", symbolName: "figure.cooldown"),
        HabitPreset(name: "力量训练", symbolName: "dumbbell")
    ]

    static let symbolOptions: [HabitPreset] = [
        HabitPreset(name: "星光", symbolName: "sparkles"),
        HabitPreset(name: "书本", symbolName: "book.closed"),
        HabitPreset(name: "跑步", symbolName: "figure.run"),
        HabitPreset(name: "喝水", symbolName: "drop.fill"),
        HabitPreset(name: "睡眠", symbolName: "bed.double.fill"),
        HabitPreset(name: "训练", symbolName: "dumbbell"),
        HabitPreset(name: "叶子", symbolName: "leaf.fill"),
        HabitPreset(name: "记录", symbolName: "square.and.pencil")
    ]
}

// MARK: - Journal and Settings

struct JournalView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigation: AppNavigationCoordinator
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Event.startDate) private var events: [Event]
    @Query(sort: \Task.createdAt, order: .reverse) private var tasks: [Task]
    @Query(sort: \Exam.startDate) private var exams: [Exam]
    @State private var selectedDate = Date.now
    @State private var displayedMonth = Date.now
    @State private var selectedID: UUID?
    @State private var isLifeSummaryPresented = false
    @AppStorage(HabitDisplayConfiguration.storageKey) private var habitDisplaySelection = ""

    var body: some View {
        journalSplitView
        .onAppear(perform: selectRequestedOrToday)
    }

    private var journalSplitView: some View {
        GeometryReader { proxy in
            // The three-column life-review layout needs room for readable
            // history, writing, and summary areas. Below this width the
            // summary becomes a native sheet instead of forcing horizontal
            // overflow in the root window.
            if proxy.size.width >= 1_080 {
                HSplitView {
                    historyPane
                        .frame(minWidth: 190, idealWidth: 250, maxWidth: 300)

                    editorPane
                        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    lifeSummaryPane
                        .frame(minWidth: 250, idealWidth: 290, maxWidth: 330, maxHeight: .infinity)
                }
            } else {
                HSplitView {
                    historyPane
                        .frame(minWidth: 190, idealWidth: 230, maxWidth: 280)

                    editorPane
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        isLifeSummaryPresented = true
                    } label: {
                        Label("今日生活", systemImage: "sidebar.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                    .padding(AppSpacing.lg)
                    .accessibilityLabel("查看当天生活摘要")
                }
            }
        }
        .background(AppColors.canvas)
        .sheet(isPresented: $isLifeSummaryPresented) {
            lifeSummaryPane
                .frame(minWidth: 360, idealWidth: 420, minHeight: 560)
        }
        .toolbar {
            ToolbarItem {
                Button(action: selectToday) {
                    Label("记录今天", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("记录今天的日记")
            }
        }
    }

    private var historyPane: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // The outer navigation bar already owns the “日记” title.
            // Omitting the eyebrow avoids duplicating it in the same vertical area.
            LifePageHeader(eyebrow: nil, title: "记录", subtitle: "留下一点只属于你的记录")
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)

            JournalMiniCalendarNavigator(
                selectedDate: selectedDate,
                displayedMonth: $displayedMonth,
                entries: entries,
                selectDate: select
            )
            .padding(.horizontal, AppSpacing.lg)

            List {
                Section {
                    Button(action: selectToday) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: todayWeather?.symbolName ?? "sun.max")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(todayWeather?.tintColor ?? AppColors.journal)
                            Text("今天")
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(AppColors.primaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("历史记录") {
                    if entries.isEmpty {
                        Text("还没有日记记录")
                            .font(AppTypography.metadata)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    ForEach(entries, id: \.id) { entry in
                        Button { select(entry) } label: {
                            JournalHistoryRow(entry: entry, isSelected: selectedID == entry.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除日记", role: .destructive) {
                                delete(entry)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(AppColors.sidebar)
    }

    private var editorPane: some View {
        JournalEditorView(
            entry: selectedEntry,
            selectedDate: selectedDate,
            courses: courses,
            events: events,
            tasks: tasks,
            exams: exams,
            onEntrySaved: { entry in
                selectedID = entry.id
            }
        )
        .background(AppColors.canvas)
    }

    private var lifeSummaryPane: some View {
        JournalLifeSummaryPanel(
            date: selectedDate,
            entries: entries,
            habits: displayedHabits,
            courses: courses,
            events: events,
            tasks: tasks,
            exams: exams,
            showCalendar: { navigation.showCalendar(on: selectedDate) },
            showTasks: navigation.showTasks
        )
    }

    private var selectedEntry: JournalEntry? {
        JournalEntryService.entry(on: selectedDate, in: entries)
    }

    private var displayedHabits: [Habit] {
        HabitDisplayConfiguration.visibleHabits(from: habits, selection: habitDisplaySelection)
    }

    private var todayWeather: WeatherCondition? {
        JournalEntryService.entry(on: .now, in: entries)?.weather
    }

    private func selectToday() {
        select(Date.now)
    }

    private func selectRequestedOrToday() {
        if let requestedDate = navigation.takeRequestedJournalDate() {
            select(requestedDate)
        } else {
            selectToday()
        }
    }

    private func select(_ entry: JournalEntry) {
        select(entry.date)
    }

    private func select(_ date: Date) {
        selectedDate = date
        displayedMonth = date
        selectedID = JournalEntryService.entry(on: date, in: entries)?.id
    }

    private func delete(_ entry: JournalEntry) {
        if selectedID == entry.id { selectedID = nil }
        try? JournalEntryService.delete(entry, in: modelContext)
    }

}

/// Keeps date lookup local to Journal while preserving the existing
/// selected-day editor state and its no-empty-entry-until-save behavior.
enum JournalMonthCalendarLayout {
    static func visibleDays(for date: Date, calendar: Calendar = .current) -> [Date] {
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let weekdayOffset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: monthStart) ?? monthStart

        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = ["日", "一", "二", "三", "四", "五", "六"]
        let firstIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }
}

private struct JournalMiniCalendarNavigator: View {
    let selectedDate: Date
    @Binding var displayedMonth: Date
    let entries: [JournalEntry]
    let selectDate: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        let days = JournalMonthCalendarLayout.visibleDays(for: displayedMonth, calendar: calendar)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: AppSpacing.xxs), count: 7)

        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Button(action: { moveMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看上个月日记")

                Text(monthStart.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide)))
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                Button(action: { moveMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看下个月日记")
            }
            .foregroundStyle(AppColors.secondaryText)

            LazyVGrid(columns: columns, spacing: AppSpacing.xxs) {
                ForEach(JournalMonthCalendarLayout.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(maxWidth: .infinity)
                }

                ForEach(days, id: \.self) { day in
                    Button { selectDate(day) } label: {
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 10, weight: calendar.isDate(day, inSameDayAs: selectedDate) ? .bold : .regular, design: .rounded))
                            .foregroundStyle(dayColor(for: day, monthStart: monthStart))
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .background(selectionBackground(for: day), in: Circle())
                            .overlay(alignment: .bottom) {
                                if hasEntry(on: day) {
                                    Circle()
                                        .fill(AppColors.journal)
                                        .frame(width: 3, height: 3)
                                        .offset(y: -2)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dayAccessibilityLabel(day))
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(AppColors.surface.opacity(0.56), in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .stroke(AppColors.surfaceBorder, lineWidth: 1)
        }
        .accessibilityLabel("日记日期导航")
    }

    private func moveMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }

    private func hasEntry(on date: Date) -> Bool {
        entries.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func dayColor(for day: Date, monthStart: Date) -> Color {
        if calendar.isDate(day, inSameDayAs: selectedDate) { return AppColors.surface }
        if !calendar.isDate(day, equalTo: monthStart, toGranularity: .month) { return AppColors.secondaryText.opacity(0.45) }
        if calendar.isDateInToday(day) { return AppColors.journal }
        return AppColors.primaryText
    }

    private func selectionBackground(for day: Date) -> Color {
        calendar.isDate(day, inSameDayAs: selectedDate) ? AppColors.journal : .clear
    }

    private func dayAccessibilityLabel(_ day: Date) -> String {
        let formattedDate = day.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day().weekday(.wide))
        return hasEntry(on: day) ? "\(formattedDate)，已有日记" : "\(formattedDate)，还没有日记"
    }
}

struct JournalHistoryRow: View {
    let entry: JournalEntry
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            Text(entry.mood?.symbol ?? "📝")
                .font(.title3)
            if let weather = entry.weather {
                Image(systemName: weather.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(weather.tintColor)
                    .accessibilityLabel("天气：\(weather.displayName)")
            }
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(entry.date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.abbreviated).day().weekday(.abbreviated)))
                    .font(AppTypography.metadata.weight(.medium))
                    .foregroundStyle(AppColors.primaryText)
                Text(entry.quote ?? entry.content ?? "空白日记")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppSpacing.xxs)
        .padding(.horizontal, AppSpacing.xxs)
        .background(isSelected ? AppColors.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }
}

struct JournalEditorView: View {
    @Environment(\.modelContext) private var modelContext
    let entry: JournalEntry?
    let selectedDate: Date
    let courses: [Course]
    let events: [Event]
    let tasks: [Task]
    let exams: [Exam]
    let onEntrySaved: (JournalEntry) -> Void

    @State private var workingEntry: JournalEntry?
    @State private var mood: Mood?
    @State private var weather: WeatherCondition?
    @State private var quote = ""
    @State private var content = ""
    @State private var importantEvents = ""
    @State private var savedAt: Date?
    @State private var isLoading = true
    @State private var isWriting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(selectedDate.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide).day().weekday(.wide)))
                        .font(AppTypography.editorialDate)
                        .foregroundStyle(AppColors.primaryText)
                    Text(Calendar.current.isDateInToday(selectedDate) ? "今天，留下一点只属于你的记录。" : "回顾这一天发生的事。")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.secondaryText)
                }

                if isWriting {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(Mood.allCases, id: \.self) { value in
                            MoodSelectionButton(
                                mood: value,
                                isSelected: mood == value,
                                select: { mood = mood == value ? nil : value }
                            )
                        }
                        if let mood {
                            Text(mood.displayName)
                                .font(AppTypography.metadata)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }

                    HStack(spacing: AppSpacing.xs) {
                        Text("天气")
                            .font(AppTypography.metadata)
                            .foregroundStyle(AppColors.secondaryText)
                        ForEach(WeatherCondition.allCases, id: \.self) { value in
                            WeatherSelectionButton(
                                weather: value,
                                isSelected: weather == value,
                                select: { weather = weather == value ? nil : value }
                            )
                        }
                        if let weather {
                            Text(weather.displayName)
                                .font(AppTypography.metadata)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }

                    JournalDailyReview(
                        date: selectedDate,
                        courses: courses,
                        events: events,
                        tasks: tasks,
                        exams: exams
                    )

                    LifeSurface(padding: AppSpacing.lg) {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            TextField("今日一句", text: $quote, prompt: Text("今天最值得记住的一句话…"))
                                .font(AppTypography.sectionTitle)
                                .textFieldStyle(.plain)
                            Divider()
                            ZStack(alignment: .topLeading) {
                                if content.isEmpty {
                                    Text("今天最值得记住的一件事是什么？")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $content)
                                    .font(AppTypography.body)
                                    .lineSpacing(5)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 280)
                            }
                        }
                    }

                    TextField("重要事件（可选）", text: $importantEvents, prompt: Text("例如：完成实验报告、和朋友吃饭"))
                        .textFieldStyle(.roundedBorder)

                    JournalDailyFootprint(
                        date: selectedDate,
                        courses: courses,
                        events: events,
                        tasks: tasks,
                        exams: exams
                    )

                    HStack {
                        Text(savedAt.map { "已自动保存 · \($0.formatted(date: .omitted, time: .shortened))" } ?? "开始记录后将自动保存")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.secondaryText)
                        Spacer()
                    }
                } else {
                    JournalEmptyState(startWriting: { isWriting = true })
                    JournalDailyFootprint(
                        date: selectedDate,
                        courses: courses,
                        events: events,
                        tasks: tasks,
                        exams: exams
                    )
                }
            }
            .padding(AppSpacing.page)
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadEntry)
        .onChange(of: entry?.id) { _, _ in loadEntry() }
        .onChange(of: selectedDate) { _, _ in loadEntry() }
        .onChange(of: mood) { _, _ in autosave() }
        .onChange(of: weather) { _, _ in autosave() }
        .onChange(of: quote) { _, _ in autosave() }
        .onChange(of: content) { _, _ in autosave() }
        .onChange(of: importantEvents) { _, _ in autosave() }
    }

    private func loadEntry() {
        isLoading = true
        workingEntry = entry
        mood = entry?.mood
        weather = entry?.weather
        quote = entry?.quote ?? ""
        content = entry?.content ?? ""
        importantEvents = entry?.importantEvents ?? ""
        savedAt = entry?.updatedAt
        isWriting = entry != nil
        DispatchQueue.main.async { isLoading = false }
    }

    private func autosave() {
        guard !isLoading else { return }
        let isBlank = mood == nil && weather == nil && quote.nilIfEmpty == nil && content.nilIfEmpty == nil && importantEvents.nilIfEmpty == nil
        guard !isBlank || workingEntry != nil else { return }

        let savedEntry = JournalEntryService.save(
            entry: workingEntry,
            date: selectedDate,
            mood: mood,
            weather: weather,
            quote: quote.nilIfEmpty,
            content: content.nilIfEmpty,
            importantEvents: importantEvents.nilIfEmpty,
            in: modelContext
        )
        workingEntry = savedEntry
        savedAt = savedEntry.updatedAt
        onEntrySaved(savedEntry)
    }

}

struct MoodSelectionButton: View {
    let mood: Mood
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Text(mood.symbol)
                .font(.title3)
                .padding(7)
                .background(isSelected ? AppColors.accent.opacity(0.18) : AppColors.primaryText.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .help(mood.displayName)
        .accessibilityLabel("心情：\(mood.displayName)")
    }
}

struct WeatherSelectionButton: View {
    let weather: WeatherCondition
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Image(systemName: weather.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .foregroundStyle(weather.tintColor)
                .frame(width: 32, height: 32)
                .background(isSelected ? weather.tintColor.opacity(0.20) : AppColors.primaryText.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .help(weather.displayName)
        .accessibilityLabel("天气：\(weather.displayName)")
    }
}

struct JournalDailyReview: View {
    let date: Date
    let courses: [Course]
    let events: [Event]
    let tasks: [Task]
    let exams: [Exam]

    var body: some View {
        let items = ScheduleAggregationService.items(for: date, courses: courses, events: events, tasks: tasks, exams: exams)
        let completedTasks = tasks.filter { $0.completedAt.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }.count
        HStack(spacing: AppSpacing.lg) {
            Label("\(items.filter { $0.category == .course }.count) 节课程", systemImage: "graduationcap")
            Label("\(items.filter { $0.category == .event }.count) 个日程", systemImage: "calendar")
            Label("完成 \(completedTasks) 项", systemImage: "checkmark.circle")
        }
        .font(AppTypography.caption)
        .foregroundStyle(AppColors.secondaryText)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.sidebar, in: Capsule())
    }
}

private struct JournalEmptyState: View {
    let startWriting: () -> Void

    var body: some View {
        LifeSurface(padding: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Image(systemName: "book.closed")
                    .font(.title2)
                    .foregroundStyle(AppColors.journal)
                Text("今天还没有留下记录。")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.primaryText)
                Text("你可以从一句话开始，需要时可打开“今日生活”查看摘要。")
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
                Button("开始记录", action: startWriting)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                    .accessibilityLabel("开始记录当天日记")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct JournalDailyFootprint: View {
    let date: Date
    let courses: [Course]
    let events: [Event]
    let tasks: [Task]
    let exams: [Exam]

    var body: some View {
        let overview = DailyLifeOverviewService.overview(
            for: date,
            journalEntries: [],
            habits: [],
            courses: courses,
            events: events,
            tasks: tasks,
            exams: exams
        )

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            LifeSectionHeader("今日足迹", subtitle: "由当天安排自动汇集")
            if overview.scheduleItems.isEmpty && overview.completedTasks.isEmpty {
                EmptyInlineView(text: "当天还没有可回顾的安排。")
            } else {
                LifeSurface(padding: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(overview.scheduleItems, id: \.id) { item in
                            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                                Text(item.startDate, format: .dateTime.hour().minute())
                                    .font(AppTypography.timelineTime)
                                    .foregroundStyle(AppColors.secondaryText)
                                Image(systemName: item.category.symbolName)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.calendar)
                                Text(item.title)
                                    .font(AppTypography.metadata.weight(.medium))
                                    .foregroundStyle(AppColors.primaryText)
                            }
                        }

                        ForEach(overview.completedTasks.filter { task in
                            !overview.scheduleItems.contains(where: { $0.id == task.id })
                        }, id: \.id) { task in
                            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.accent)
                                    .frame(width: 43, alignment: .trailing)
                                Text(task.title)
                                    .font(AppTypography.metadata.weight(.medium))
                                    .foregroundStyle(AppColors.primaryText)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct JournalLifeSummaryPanel: View {
    @Environment(\.modelContext) private var modelContext
    let date: Date
    let entries: [JournalEntry]
    let habits: [Habit]
    let courses: [Course]
    let events: [Event]
    let tasks: [Task]
    let exams: [Exam]
    let showCalendar: () -> Void
    let showTasks: () -> Void

    var body: some View {
        let overview = DailyLifeOverviewService.overview(
            for: date,
            journalEntries: entries,
            habits: habits,
            courses: courses,
            events: events,
            tasks: tasks,
            exams: exams
        )

        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                LifePageHeader(eyebrow: nil, title: "今日生活", subtitle: "客观足迹与主观记录")

                LifeSurface(padding: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        if let mood = overview.journalEntry?.mood {
                            Label("\(mood.symbol) \(mood.displayName)", systemImage: "face.smiling")
                                .font(AppTypography.metadata)
                                .foregroundStyle(AppColors.primaryText)
                        } else {
                            Label("尚未记录心情", systemImage: "face.dashed")
                                .font(AppTypography.metadata)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                        if let weather = overview.journalEntry?.weather {
                            Label(weather.displayName, systemImage: weather.symbolName)
                                .font(AppTypography.metadata)
                                .foregroundStyle(weather.tintColor)
                        }
                        Divider()
                        Label("\(overview.scheduleItems.filter { $0.category == .course }.count) 节课程", systemImage: "graduationcap")
                        Label("\(overview.scheduleItems.filter { $0.category == .event }.count) 个日程", systemImage: "calendar")
                        Label("任务 \(overview.completedTasks.count) / \(overview.dailyTasks.count)", systemImage: "checkmark.circle")
                    }
                    .font(AppTypography.metadata)
                    .foregroundStyle(AppColors.secondaryText)
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    LifeSectionHeader("今日习惯", subtitle: overview.totalHabitCount == 0 ? "尚未添加" : "\(overview.completedHabitCount) / \(overview.totalHabitCount) 完成")
                    if overview.habitStatuses.isEmpty {
                        EmptyInlineView(text: "还没有可追踪的习惯。")
                    } else {
                        LifeSurface(padding: AppSpacing.md) {
                            VStack(spacing: AppSpacing.xs) {
                                ForEach(overview.habitStatuses) { status in
                                    HabitStatusRow(status: status) {
                                        HabitService.toggle(status.habit, on: date, in: modelContext)
                                    }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        LifeSectionHeader("今日任务", subtitle: overview.dailyTasks.isEmpty ? "没有任务" : "\(overview.completedTasks.count) 项已完成")
                        Button("查看", action: showTasks)
                            .buttonStyle(.plain)
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(AppColors.accent)
                    }
                    if !overview.dailyTasks.isEmpty {
                        LifeSurface(padding: AppSpacing.md) {
                            VStack(spacing: AppSpacing.xs) {
                                ForEach(overview.dailyTasks.prefix(5), id: \.id) { task in
                                    Button(action: showTasks) {
                                        HStack(spacing: AppSpacing.xs) {
                                            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(task.status == .completed ? AppColors.accent : AppColors.secondaryText)
                                            Text(task.title)
                                                .font(AppTypography.metadata)
                                                .foregroundStyle(AppColors.primaryText)
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("查看任务：\(task.title)")
                                }
                            }
                        }
                    }
                }

                Button(action: showCalendar) {
                    Label("在日历中查看这一天", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppColors.accent)
                .accessibilityLabel("在日历中查看选中日期")
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.sidebar.opacity(0.62))
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("launchDestination") private var launchDestination = AppDestination.today.rawValue
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("weekStartsMonday") private var weekStartsMonday = true
    @AppStorage("use24HourTime") private var use24HourTime = true
    @State private var importConfirmationPresented = false
    @State private var importFailureMessage: String?
    @State private var importSuccessPresented = false
    @State private var importSuccessMessage = ""
    @State private var restoreConfirmationPresented = false
    @State private var backupCandidate: LifeOSBackupArchive?
    @State private var backupFailureMessage: String?
    @State private var backupSuccessMessage: String?
    @State private var automaticBackups: [LifeOSAutomaticBackupInfo] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                LifePageHeader(eyebrow: nil, title: "偏好设置", subtitle: "让 LifeOS 更贴近你的生活节奏")

                settingsSection("通用") {
                    Picker("启动时打开", selection: $launchDestination) {
                        Text("今天").tag(AppDestination.today.rawValue)
                        Text("日历").tag(AppDestination.calendar.rawValue)
                        Text("任务").tag(AppDestination.tasks.rawValue)
                    }
                    Toggle("一周从星期一开始", isOn: $weekStartsMonday)
                    Toggle("使用 24 小时制", isOn: $use24HourTime)
                }

                settingsSection("外观") {
                    Picker("外观", selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                settingsSection("通知") {
                    Toggle("任务提醒", isOn: .constant(false)).disabled(true)
                    Toggle("课程提醒", isOn: .constant(false)).disabled(true)
                    Text("通知将在后续小版本开放。")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
                }

                settingsSection("自动数据保护") {
                    Text("LifeOS 会在每天启动时和退出前更新一份本机快照；清空导入或恢复前也会创建保护点，无需手动保存。")
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                    if let latestBackup = automaticBackups.first {
                        Label("最近保护：\(latestBackup.dateDescription) · \(latestBackup.kind.displayName)", systemImage: latestBackup.kind.symbolName)
                            .font(AppTypography.metadata)
                            .foregroundStyle(AppColors.secondaryText)
                    } else {
                        Label("尚未创建自动保护，打开应用后会自动完成。", systemImage: "clock.arrow.circlepath")
                            .font(AppTypography.metadata)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    Divider()
                    HStack {
                        Button("立即创建快照", action: createAutomaticSnapshot)
                            .accessibilityLabel("立即创建本机自动保护快照")
                        Button("刷新", action: reloadAutomaticBackups)
                            .accessibilityLabel("刷新自动保护列表")
                        Spacer()
                    }
                    if automaticBackups.isEmpty {
                        EmptyInlineView(text: "最近还没有可恢复的本机快照。")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(automaticBackups) { backup in
                                automaticBackupRow(backup)
                                if backup.id != automaticBackups.last?.id { Divider() }
                            }
                        }
                        .background(AppColors.sidebar.opacity(0.34), in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }
                }

                settingsSection("迁移与外部备份") {
                    Text("需要换设备、长期存档或从外部文件恢复时，再使用下面的完整备份文件。")
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                    HStack {
                        Button("导出完整备份…", action: exportBackup)
                            .accessibilityLabel("导出完整数据备份")
                        Button("从外部备份恢复…", action: chooseBackupToRestore)
                            .accessibilityLabel("从外部备份恢复数据")
                    }
                }

                settingsSection("人工测试数据") {
                    Text("仅用于测试。导入前会先自动保护当前所有数据。")
                        .font(AppTypography.metadata)
                        .foregroundStyle(AppColors.secondaryText)
                    Button("清空并导入人工测试数据…") { importConfirmationPresented = true }
                        .foregroundStyle(AppColors.deadline)
                        .accessibilityLabel("清空现有数据并导入人工测试数据")
                }
            }
            .padding(AppSpacing.page)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .background(AppColors.canvas)
        .onAppear(perform: reloadAutomaticBackups)
        .confirmationDialog("清空现有数据并导入？", isPresented: $importConfirmationPresented, titleVisibility: .visible) {
            Button("清空并导入", role: .destructive, action: importManualTestData)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会删除本机现有的课程、课次、作业、考试、任务、日程、日记和标签，且无法恢复。")
        }
        .alert("导入完成", isPresented: $importSuccessPresented) {
            Button("好") {}
        } message: {
            Text(importSuccessMessage)
        }
        .alert("导入失败", isPresented: Binding(
            get: { importFailureMessage != nil },
            set: { if !$0 { importFailureMessage = nil } }
        )) {
            Button("好") { importFailureMessage = nil }
        } message: {
            Text(importFailureMessage ?? "未知错误")
        }
        .confirmationDialog("用备份替换当前数据？", isPresented: $restoreConfirmationPresented, titleVisibility: .visible) {
            Button("恢复并替换当前数据", role: .destructive, action: restoreBackup)
            Button("取消", role: .cancel) { backupCandidate = nil }
        } message: {
            if let backupCandidate {
                Text("备份创建于 \(backupCandidate.exportedAtDescription)，包含 \(backupCandidate.summary)。恢复前会自动备份当前数据，然后替换本机内容与偏好设置。")
            } else {
                Text("恢复前会自动备份当前数据，然后替换本机内容与偏好设置。")
            }
        }
        .alert("数据操作完成", isPresented: Binding(
            get: { backupSuccessMessage != nil },
            set: { if !$0 { backupSuccessMessage = nil } }
        )) {
            Button("好") { backupSuccessMessage = nil }
        } message: {
            Text(backupSuccessMessage ?? "")
        }
        .alert("数据操作失败", isPresented: Binding(
            get: { backupFailureMessage != nil },
            set: { if !$0 { backupFailureMessage = nil } }
        )) {
            Button("好") { backupFailureMessage = nil }
        } message: {
            Text(backupFailureMessage ?? "未知错误")
        }
    }

    private func importManualTestData() {
        do {
            let recoveryURL = try LifeOSBackupService.createRecoveryPoint(
                from: modelContext,
                kind: .beforeTestDataImport
            )
            try ManualTestDataService.replaceExistingData(in: modelContext)
            importSuccessMessage = "已清空现有数据并导入人工测试数据。导入前的数据已自动保护为：\(recoveryURL.lastPathComponent)"
            importSuccessPresented = true
            reloadAutomaticBackups()
        } catch {
            importFailureMessage = error.localizedDescription
        }
    }

    private func createAutomaticSnapshot() {
        do {
            let url = try LifeOSBackupService.createDailySnapshot(from: modelContext)
            reloadAutomaticBackups()
            backupSuccessMessage = "已更新本机自动保护：\(url.lastPathComponent)"
        } catch {
            backupFailureMessage = error.localizedDescription
        }
    }

    private func reloadAutomaticBackups() {
        automaticBackups = LifeOSBackupService.automaticBackups()
    }

    private func automaticBackupRow(_ backup: LifeOSAutomaticBackupInfo) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: backup.kind.symbolName)
                .foregroundStyle(AppColors.accent)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(backup.kind.displayName)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.primaryText)
                Text("\(backup.dateDescription) · \(backup.archive.summary)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: AppSpacing.sm)
            Button("恢复") {
                backupCandidate = backup.archive
                restoreConfirmationPresented = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("恢复\(backup.kind.displayName)\(backup.dateDescription)的备份")
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "导出 LifeOS 完整备份"
        panel.message = "备份文件只保存在你选择的位置。"
        panel.prompt = "导出"
        panel.nameFieldStringValue = LifeOSBackupService.defaultFileName()
        panel.allowedContentTypes = [UTType(filenameExtension: LifeOSBackupService.fileExtension) ?? .json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try LifeOSBackupService.writeBackup(from: modelContext, to: url)
            backupSuccessMessage = "已导出完整备份：\(url.lastPathComponent)"
        } catch {
            backupFailureMessage = error.localizedDescription
        }
    }

    private func chooseBackupToRestore() {
        let panel = NSOpenPanel()
        panel.title = "选择 LifeOS 备份"
        panel.message = "选择之前导出的 .lifeosbackup 文件。"
        panel.prompt = "选择备份"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: LifeOSBackupService.fileExtension) ?? .json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            backupCandidate = try LifeOSBackupService.loadBackup(from: url)
            restoreConfirmationPresented = true
        } catch {
            backupFailureMessage = error.localizedDescription
        }
    }

    private func restoreBackup() {
        guard let backupCandidate else { return }

        do {
            let result = try LifeOSBackupService.restore(backupCandidate, into: modelContext)
            result.restoredPreferences.apply()
            launchDestination = result.restoredPreferences.launchDestination
            appearance = result.restoredPreferences.appearance
            weekStartsMonday = result.restoredPreferences.weekStartsMonday
            use24HourTime = result.restoredPreferences.use24HourTime
            backupSuccessMessage = "已恢复备份。恢复前的数据已自动保存为：\(result.automaticBackupURL.lastPathComponent)"
            self.backupCandidate = nil
            reloadAutomaticBackups()
        } catch {
            backupFailureMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            LifeSectionHeader(title)
            LifeSurface(padding: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.sm, content: content)
            }
        }
    }
}

// MARK: - Shared UI

struct TimelineList: View {
    let items: [ScheduleItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Text(item.startDate, format: .dateTime.hour().minute())
                        .font(AppTypography.timelineTime)
                        .foregroundStyle(AppColors.secondaryText)
                        .frame(width: 54, alignment: .leading)

                    VStack(spacing: 0) {
                        Circle()
                            .fill(categoryColor(item.category))
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        Rectangle()
                            .fill(AppColors.divider.opacity(item.id == items.last?.id ? 0 : 0.8))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: 10)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(item.title)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.primaryText)
                        Text(item.category.label)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.secondaryText)
                    }

                    Spacer(minLength: AppSpacing.sm)

                    if let end = item.endDate {
                        Text(end, format: .dateTime.hour().minute())
                            .font(AppTypography.caption.monospacedDigit())
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                .frame(minHeight: 42, alignment: .top)
                .padding(.vertical, AppSpacing.xs)
            }
        }
    }

    private func categoryColor(_ category: ScheduleCategory) -> Color {
        switch category {
        case .course: AppColors.course
        case .event: AppColors.calendar
        case .task: AppColors.task
        case .exam: AppColors.deadline
        }
    }
}

struct EmptyInlineView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppTypography.metadata)
            .foregroundStyle(AppColors.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
    }
}

private extension String { var nilIfEmpty: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value } }
