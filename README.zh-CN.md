# Pace

**Know what you can spend today.**

![License](https://img.shields.io/badge/license-MIT-blue)
![Version](https://img.shields.io/badge/version-0.1.0-blue)
![Android CI](https://github.com/CarlOpenLab/pace/actions/workflows/android.yml/badge.svg)
![iOS CI](https://github.com/CarlOpenLab/pace/actions/workflows/ios.yml/badge.svg)

[English](README.md) · 中文

原生 Android + 原生 iOS 的每日预算记账 App。一个数字回答「今天还能花多少」。账本数据只保存在设备本地；AI 是可选辅助，默认关闭。

产品落地页：<https://carlopenlab.github.io/pace/>

- **预算诚实计算。** 今日剩余 = 今日预算 − 计入预算的净支出；当日结余默认不结转、超支不自动扣减明日；改预算从指定生效日开始，不重写历史；预算引擎不依赖网络和 AI。
- **记账只要几秒。** 浮起的「记一笔」；AI 可把一句话变成账单草稿，但写入前必须经你确认；退款关联原账单避免重复计算；转账与信用卡还款不计入消费。
- **本地优先，隐私默认。** 无账号、无云端账本、无埋点。随时导出带版本号的完整 JSON，见 [docs/AI_PRIVACY.md](docs/AI_PRIVACY.md)。
- **一个共享核心。** 两端共享同一个 Kotlin Multiplatform 模块：预算计算、金额规则、日期归属、导入导出、指纹去重，保证 Android 和 iOS 结果一致。固定验收案例（48 个测试）在 `shared/src/commonTest` 与 [docs/EDGE_CASES.md](docs/EDGE_CASES.md)。

产品与技术规划见 [PLAN.md](PLAN.md)，跨端契约见 [docs/](docs/)。

> Pace 处于开发阶段（v0.1.0），暂无应用商店上架——可直接安装的构建产物来自 CI。

## 仓库结构

```text
├── shared/          # Kotlin Multiplatform 共享业务核心（预算/金额/统计/导入导出/指纹去重）
├── androidApp/      # Kotlin + Jetpack Compose 原生 Android 客户端
├── iosApp/          # Swift + SwiftUI 原生 iOS 客户端（XcodeGen 工程）
├── docs/            # 跨端契约：预算规则 / 数据模型 / 导出格式 / AI 隐私 / 边界案例
├── src/ 等          # 现有 Web/PWA 原型（React + Vite），迁移期间仅作参考
└── PLAN.md          # 产品与技术规划
```

两个原生客户端不共享 UI，但预算计算、金额规则、日期归属、导入导出全部来自同一个 `shared` 模块，保证两端结果一致。

## CI / 安装包

每次推送后 GitHub Actions 会构建可直接安装的产物（[Actions](https://github.com/CarlOpenLab/pace/actions) 页面对应 run 的 Artifacts）：

| Workflow | 产物 | 安装方式 |
| --- | --- | --- |
| `android` | `pace-android-debug-apk`（debug APK） | 下载后直接在 Android 设备安装 |
| `ios` | `pace-ios-unsigned-ipa`（未签名 IPA） | 用 AltStore / Sideloadly 等自签后安装 |
| `ios` | `pace-ios-simulator-app` | 解压拖入 iOS 模拟器运行 |
| `web` | — | Web 原型类型检查 / 测试 / 构建 |

## 原生端开发

Android（需要 JDK 17 + Android SDK 34）：

```bash
./gradlew :androidApp:assembleDebug
```

iOS（需要 macOS + Xcode 15+，详见 [iosApp/README.md](iosApp/README.md)）：

```bash
./gradlew :shared:assembleXCFramework
cd iosApp && xcodegen generate && open iosApp.xcodeproj
```

共享核心测试（JVM 即可运行）：

```bash
./gradlew :shared:testDebugUnitTest
```

## Web 原型（参考实现）

Offline-first 的账单导入 / 分类 / 统计原型，业务规则已提取进 `shared`：

```bash
npm install
npm run dev      # 开发
npm test         # 测试
npm run build    # 构建
```

## 文档

- [PLAN.md](PLAN.md) — 产品定位、路线、平台与协作决策
- [docs/BUDGET_RULES.md](docs/BUDGET_RULES.md) — 预算计算的精确规则
- [docs/DATA_MODEL.md](docs/DATA_MODEL.md) — 字段、枚举与金额/日期规则
- [docs/EXPORT_FORMAT.md](docs/EXPORT_FORMAT.md) — 带版本号的 JSON 导出格式
- [docs/AI_PRIVACY.md](docs/AI_PRIVACY.md) — AI 能做什么、不能做什么
- [docs/DESIGN.md](docs/DESIGN.md) — 视觉与交互规范

## 许可

[MIT](LICENSE)
