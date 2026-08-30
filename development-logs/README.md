# 开发日志

每个工作日使用独立文件记录开发完成事项、待办、验证结果、决策与阻塞项。

文件格式：`YYYY-MM-DD.md`。

请通过以下命令写入，脚本会在当天首次使用时自动创建日志：

```zsh
./scripts/log-development-day.sh todo "实现 Today 时间轴"
./scripts/log-development-day.sh done "完成 Today 时间轴并通过构建"
./scripts/log-development-day.sh note "待确认：课程调课规则"
```

不要删除、覆盖或合并历史日志。
