.PHONY: log-todo log-done log-note

# Example: make log-todo NOTE="实现 Today 时间轴"
log-todo:
	@test -n "$(NOTE)" || (echo "请提供 NOTE，例如：make log-todo NOTE=\"实现 Today 时间轴\""; exit 2)
	@./scripts/log-development-day.sh todo "$(NOTE)"

log-done:
	@test -n "$(NOTE)" || (echo "请提供 NOTE，例如：make log-done NOTE=\"完成 Today 时间轴\""; exit 2)
	@./scripts/log-development-day.sh done "$(NOTE)"

log-note:
	@test -n "$(NOTE)" || (echo "请提供 NOTE，例如：make log-note NOTE=\"记录验证结果\""; exit 2)
	@./scripts/log-development-day.sh note "$(NOTE)"
