# 本机发行与 GitHub 发布指南

> 适用于 LifeOS 的本机 Release 构建。当前项目未进行 Apple Developer ID 公证，因此发行产物仅保证在构建它的这台 Mac 上可直接使用；向其他 Mac 分发前需另行完成 Developer ID 签名与公证。

## 发布前检查

1. 工作区只包含本次准备发布的产品代码、测试、文档和开发日志；交互演示 HTML 不纳入发行提交。
2. 运行完整测试：

   ```zsh
   xcodebuild -project LifeOS.xcodeproj -scheme LifeOS \
     -destination 'platform=macOS' -derivedDataPath /private/tmp/lifeos-derived test
   ```

3. 在常用窗口尺寸手工检查 Today、任务、日历、课表、课程、日记、设置与备份恢复提示。

## 生成本机可用的 Release 应用

```zsh
xcodebuild -project LifeOS.xcodeproj -scheme LifeOS \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/lifeos-release build

mkdir -p dist
ditto /private/tmp/lifeos-release/Build/Products/Release/LifeOS.app dist/LifeOS.app
codesign --verify --deep --strict --verbose=2 dist/LifeOS.app
open dist/LifeOS.app
```

`dist/LifeOS.app` 是可直接双击运行的本机发行版本。`dist/` 仅保存构建产物，不纳入 Git。

## GitHub 更新

1. 不暂存 `work/*demo*.html` 等交互演示文件。
2. 暂存本次产品代码、测试、文档与开发日志，创建聚焦提交。
3. 在推送前确认：

   ```zsh
   git status --short
   git diff --cached --check
   git log --oneline -1
   ```

4. 推送主分支：

   ```zsh
   git push origin main
   ```

## 对其他 Mac 分发的限制

当前“本机签名”不等同于可公开分发的发行签名。若需要让其他 Mac 默认通过 Gatekeeper 验证，必须在未来使用 Apple Developer Program 的 Developer ID Application 证书签名并上传 Apple Notary Service 公证；这一步不应通过关闭系统安全设置来绕过。
