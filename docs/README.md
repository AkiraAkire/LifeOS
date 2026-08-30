# LifeOS 项目文档

本目录是 LifeOS 的唯一项目标准来源。产品、交互、技术实现、数据关系和验收规则发生变化时，应先更新对应文档，再实施代码变更。当前文档基线更新至 **2026-08-30**，与已交付的本地备份、课表学期规则和日历／日记／习惯联动保持一致。

| 文件 | 用途 |
| --- | --- |
| `01-product-requirements.md` | V1 产品范围、核心使用闭环与功能边界 |
| `02-technical-architecture.md` | SwiftUI / SwiftData 架构、分层与扩展原则 |
| `03-ui-ux-design-system.md` | macOS 原生交互、视觉语言与中文文案规范 |
| `04-development-roadmap.md` | 已完成阶段、后续推进顺序和每次变更流程 |
| `05-data-model.md` | SwiftData 实体、字段、关系与数据一致性规则 |
| `06-testing-and-quality.md` | 构建、测试、手工验收和回归要求 |
| `07-decision-log.md` | 已确认的重要产品与技术决策 |
| `08-manual-test-dataset.md` | 人工测试数据集、录入顺序与验证项 |

日常执行记录不放在此目录，而是写入 `../development-logs/`。
