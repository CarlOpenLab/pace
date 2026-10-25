# Pace

Know what you can spend today.

原生 Android + 原生 iOS 的每日预算记账 App。账本数据只保存在设备本地；AI 是可选辅助，默认关闭。产品规划见 [PLAN.md](PLAN.md)，跨端契约见 [docs/](docs/)。

## 仓库结构

```text
├── shared/          # Kotlin Multiplatform 共享业务核心（预算/金额/统计/导入导出/指纹去重）
├── androidApp/      # Kotlin + Jetpack Compose 原生 Android 客户端
├── iosApp/          # Swift + SwiftUI 原生 iOS 客户端（XcodeGen 工程）
├── docs/            # 跨端契约：预算规则 / 数据模型 / 导出格式 / AI 隐私 / 边界案例
├── src/ 等          # 现有 Web/PWA 原型（React + Vite），迁移期间仅作参考
└── PLAN.md          # 产品与技术规划
```

两个原生客户端不共享 UI，但预算计算、金额规则、日期归属、导入导出全部来自同一个 `shared` 模块，保证两端结果一致。共享核心的固定验收案例（48 个测试）见 `shared/src/commonTest` 与 `docs/EDGE_CASES.md`。

## CI / 安装包

每次推送后 GitHub Actions 会构建可直接安装的产物（仓库 Actions 页面对应 run 的 Artifacts）：

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
