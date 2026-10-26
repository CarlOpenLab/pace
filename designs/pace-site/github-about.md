# GitHub 仓库侧栏 About — 文案与设置

位置：仓库页右侧 About 区（`Settings → General` 顶部也可编辑），以及 `Settings → General → Social preview`。

## Description（侧栏一句话）

```
Daily-budget expense tracker for Android & iOS. Your ledger stays on your device; AI is optional and off by default.
```

- 约 120 字符，侧栏单行放得下（上限 350，但一行内最易读）。
- 与 README 首行、落地页 hero 副文案同一口径。

## Topics（建议 15 个，全部小写、连字符）

```
android  ios  kotlin-multiplatform  jetpack-compose  swiftui
expense-tracker  budget  budget-tracker  personal-finance
local-first  offline-first  privacy  kmp  daily-budget  money
```

> GitHub 最多 20 个；以上 15 个覆盖「平台 / 技术 / 品类 / 立场」四类检索词。优先挂前 10 个。

## Releases / website 字段

- **Website**：GitHub Pages 已启用（main 分支 `/docs` 目录），填 `https://carlopenlab.github.io/pace/`。
- 落地页生产版在 [`docs/index.html`](../../docs/index.html)，与 [`Landing Page.html`](Landing%20Page.html) 内容一致；改设计后复制同步即可（两文件应保持 diff 为空）。

## Social preview

- 用 [`social-preview.html`](social-preview.html) 渲染出 1280×640 的 PNG（浏览器打开 → 截图，或用无头浏览器导出 `social-preview.png`）。
- 上传入口：`Settings → General → Social preview → Edit → Upload a new image`。
- 深色底在 GitHub 浅色/深色两种界面下都成立；文件请压在 1MB 以内。

## 徽标（README 顶部，随版本三处同步规则）

```
![License](https://img.shields.io/badge/license-MIT-blue)
![Version](https://img.shields.io/badge/version-0.1.0-blue)
![Android CI](https://github.com/CarlOpenLab/pace/actions/workflows/android.yml/badge.svg)
![iOS CI](https://github.com/CarlOpenLab/pace/actions/workflows/ios.yml/badge.svg)
```

> PLAN.md 约定版本号三处一起改：`iosApp/project.yml` 的 `MARKETING_VERSION`、README 徽标、CHANGELOG。发新 tag 时同步上面的 Version 徽标。
