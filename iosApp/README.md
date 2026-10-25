# Pace iOS（SwiftUI + KMP 共享核心）

原生 iOS 客户端：Swift + SwiftUI，业务核心（预算、金额、统计、导入导出）全部来自 `../shared` Kotlin Multiplatform 模块编译出的 `shared.xcframework`。

## 本地开发

```bash
# 1. 构建共享框架（产出 shared/build/XCFrameworks/{debug,release}/shared.xcframework）
./gradlew :shared:assembleXCFramework

# 2. 生成 Xcode 工程（工程文件不进 git，由 project.yml 生成）
brew install xcodegen
cd iosApp && xcodegen generate

# 3. 打开工程
open iosApp.xcodeproj
```

> 工程默认关闭代码签名（`CODE_SIGNING_ALLOWED=NO`）。真机调试请在 Xcode 中选择你的开发团队后重新签名。

## 安装包

CI（`.github/workflows/ios.yml`）在每次推送后产出两个产物（Actions → 对应 run → Artifacts）：

| 产物 | 用途 |
| --- | --- |
| `pace-ios-unsigned-ipa` | 未签名 IPA（arm64 真机）。用 AltStore / Sideloadly 等自签工具安装到设备 |
| `pace-ios-simulator-app` | 模拟器 App（Debug-iphonesimulator），解压后拖入模拟器即可运行 |

## 架构说明

- `LedgerStore` 持有 `LedgerApi`（来自共享框架），所有账本操作走共享核心，保证与 Android 结果一致。
- 数据库为应用沙盒内的 SQLite（`pace.db`），无任何网络请求。
- 共享 API 见 `../docs/DATA_MODEL.md`；金额为最小货币单位 Int64，禁止浮点。
