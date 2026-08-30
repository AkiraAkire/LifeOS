# LifeOS Agent Working Guide

This repository contains **LifeOS**, a Simplified-Chinese, native macOS personal life-management application. The product is developed incrementally: stable, buildable milestones take precedence over feature breadth.

## Required reading before implementation

Read the applicable files in `docs/` before changing product code:

| Topic | Standard file |
| --- | --- |
| Product scope and priorities | `docs/01-product-requirements.md` |
| Architecture and implementation boundaries | `docs/02-technical-architecture.md` |
| macOS interaction and visual standards | `docs/03-ui-ux-design-system.md` |
| Milestones and execution order | `docs/04-development-roadmap.md` |
| SwiftData entities and relationship rules | `docs/05-data-model.md` |
| Tests, verification, and quality gates | `docs/06-testing-and-quality.md` |
| Product and technical decisions | `docs/07-decision-log.md` |

## Daily development log (mandatory)

Development activity is recorded in `development-logs/YYYY-MM-DD.md`.

1. At the start of a meaningful task, run:
   ```zsh
   ./scripts/log-development-day.sh todo "Describe the task"
   ```
2. When a task is completed, run:
   ```zsh
   ./scripts/log-development-day.sh done "Describe the completed work"
   ```
3. Record key implementation notes, decisions, blockers, or verification results with:
   ```zsh
   ./scripts/log-development-day.sh note "Describe the result or decision"
   ```
4. Before handing work off, ensure the day log contains completed items, remaining items, and any blocker.

The script creates the current day’s log automatically when it does not yet exist. Never replace or delete prior daily logs to make a task look clean.

## Git and verification workflow (mandatory)

- After every completed change, create one focused Git commit that contains the corresponding source, documentation, test, and development-log updates. Do not mix unrelated existing worktree changes into that commit.
- Every code or behavior change must add or update its relevant automated tests. Before handing work to the user, run all relevant tests and validation steps successfully; do not report completion with a known failing test, build, or verification step.
- For documentation-only or workflow-only changes where no automated test applies, record the reason and the verification performed in the daily development log before committing.

## Implementation rules

- Build V1 only in the order stated in `docs/04-development-roadmap.md`; do not begin V2/V3 work early.
- Use Swift, SwiftUI, SwiftData, Apple frameworks, and a lightweight MVVM structure. Avoid third-party dependencies unless explicitly approved.
- UI-visible copy, menus, settings, validation, and empty states must be in Simplified Chinese. Source files, symbols, model fields, and comments use English.
- Treat Today as the primary surface. Calendar, Tasks, Courses, and Journal must share model relationships rather than duplicate data.
- Keep one durable source of truth for each item. Aggregate calendar and Today display data through services/view models.
- Make focused changes. Do not perform broad refactors while implementing an unrelated feature.
- Add or update tests for new domain rules. Build and test the affected target before declaring work complete.
- Record a decision in `docs/07-decision-log.md` when it changes product scope, data-model semantics, storage/migration strategy, or a documented UI convention.

## Completion checklist

- [ ] Relevant standards were read.
- [ ] The task was logged in today’s development log.
- [ ] A focused Git commit was created for the completed change.
- [ ] The affected target builds successfully.
- [ ] Relevant tests pass, or an explicit limitation is logged.
- [ ] UI copy is Simplified Chinese and follows the macOS design standard.
- [ ] Follow-up work is recorded as a todo in today’s log.
