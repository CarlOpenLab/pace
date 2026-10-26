# Pace App Intents 机会分析

> 分析日期：2026-10-26

## 现有 App Intents 清单

当前 App 声明 **0 个 App Intents 动作**，没有为 Shortcuts、App Shortcuts、Spotlight、Siri、小组件或控制项声明任何入口，也没有采用任何 Apple Intelligence schema。

搜索范围与结果：

- 检查了 `iosApp/iosApp/` 下全部 Swift 文件、`iosApp/iosApp/Info.plist`、`iosApp/project.yml`，以及 `shared/src/` 下的 Kotlin 源文件。
- 搜索了 `AppIntent`、`AppShortcutsProvider`、`AppShortcut`、`AppEntity`、`EntityQuery`、`AppEnum`、`IntentParameter`、`@Parameter`、`AssistantIntent`、`AssistantSchema`、`IndexedEntity`、`CSSearchableIndex`、`indexAppEntities`、`NSUserActivity`、`Spotlight`、`AppSchema` 等声明与调用，未发现匹配。
- 工程中没有 Intents extension、WidgetKit extension、Control widget、Share extension，也没有 `.entitlements` 文件；`iosApp/project.yml` 只有一个主 App target。
- 以上只说明“代码没有声明 App Intent”。它不代表 Shortcuts、Spotlight 或 Siri 中会出现任何动作；这些系统入口还需要后续实现与签名设备验证。

| 业务动作 | Intent / shortcut / entity / query 路径与符号 | 当前接了什么（入口、App Shortcut、schema） | 缺失部分 / 证据限制 |
| --- | --- | --- | --- |
| （无） | 未发现 `AppIntent`、`AppShortcutsProvider`、`AppEntity`、`EntityQuery`、`AppEnum` 或 schema 声明 | 无 | 需要从零新增 Intent 层；当前没有 Shortcuts / Spotlight / Siri 入口 |

## 项目与范围

- 项目：`Pace`，现有 iOS App（未提供 brief，无法确认是否由模板导入）；分析日期 **2026-10-26**。
- 代码基线：`main` 分支，提交 **23e6703**（`23e6703dd6f704c896c7467a4d7c44a7a2236a9d`），工作树干净；这是首次分析，项目根目录此前没有 `intent-opportunities.md`。
- 分析原因：评估 Pace 现有功能中哪些值得通过 App Intents 暴露给 Shortcuts、Spotlight、Siri，以及是否适合采用 Apple Intelligence schema。
- Brief 与实现的关系：没有单独 brief；`PLAN.md` 只是产品规划。`PLAN.md` 第 3、7、316 行把 iOS 的 “Siri/App Intents” 列为平台增强方向，但当前代码完全没有实现 Intent 层。`docs/AI_PRIVACY.md` 明确规定 AI 不得绕过用户确认直接写入账本，这条规则会影响“一句话记账”类 Intent 的设计。
- 检查过的入口与代码：`HomeView.swift`（今日预算卡、今日账单）、`AddView.swift`（手动记账、编辑、退款关联）、`QuickAddView.swift`（一句话输入）、`DraftReviewView.swift`（草稿确认入账）、`BillsView.swift`（周/月/全部、搜索、编辑、删除、撤销）、`StatsView.swift`（周/月统计）、`SettingsView.swift`（预算、导出、导入、清空）、`QuickAddSettingsView.swift` / `AiSettings.swift` / `AiDraftClient.swift`（可选 BYOK 模型）、`PaceApp.swift`（`LedgerStore`、`AppState`、`RootView`）。
- 检查过的共享逻辑：`shared/src/commonMain/kotlin/pace/shared/LedgerApi.kt`（账本门面）、`budget/BudgetEngine.kt`、`statistics/StatsEngine.kt`、`classifier/KeywordClassifier.kt`、`ai/SentenceDraftParser.kt`、`money/Money.kt`、`model/Models.kt`、`util/Ids.kt`、`datetime/PaceDates.kt`、`iosMain/kotlin/pace/shared/IosDriverFactory.kt`。
- 数据与授权：账本是设备内 SQLite（`IosDriverFactory` 使用 `NativeSqliteDriver(PaceDatabase.Schema, "pace.db")`），没有账号、登录、服务端账本或按用户划分的数据范围；代码中没有 `LocalAuthentication` / 登录检查。AI 是可选 BYOK，Key 存在 Keychain（`AiSettings.swift` 的 `AiKeychain`），但不属于本次首批候选。
- 未检查 / 无法检查：本分析环境没有 Xcode 和 iPhoneOS SDK，无法读取 Swift interface、`AppIntentSchemas.sqlite` 或运行 `xcodebuild`；没有构建、没有在 Simulator/真机运行、没有验证 Siri、Shortcuts、Spotlight、Action Button 或签名行为。Apple 在线文档可访问，本文的可用性声明来自文档，不是项目 SDK 声明或运行结果。

| Target / 配置 | 相关源码 | Deployment target | SDK / 工具链证据 | 未知项 |
| --- | --- | --- | --- | --- |
| `iosApp` 主 App（bundle `com.pace.app`，产品名 `Pace`） | `iosApp/iosApp/*.swift`、`Info.plist` | iOS **26.0**（`project.yml` 的 `deploymentTarget`） | `project.yml` 声明 `SWIFT_VERSION: "5.9"`、XcodeGen 生成工程、`CODE_SIGNING_ALLOWED: NO`；仓库不包含 `.xcodeproj`；CI 在 `macos-14` 上选择最新 Xcode（`.github/workflows/ios.yml`），实际版本未记录 | 实际 Xcode/SDK 版本、App Intents metadata 处理、Swift 5.9 下的编译结果、签名/Team ID |
| `shared` KMP 共享核心 | `shared/src/commonMain/kotlin/pace/shared/**`、`shared/src/iosMain/kotlin/pace/shared/IosDriverFactory.kt` | 不单独适用（随 App） | `project.yml` 引用 `../shared/build/XCFrameworks/release/shared.xcframework`；当前工作区没有已生成的 XCFramework 和 `.xcodeproj` | 需要先运行 `./gradlew :shared:assembleSharedReleaseXCFramework` 和 `xcodegen generate` 才能编译 |
| 扩展 / 小组件 / 控制项 | 未发现 target 或源码 | 无 | 无 | 无 WidgetKit、Control widget、Intents extension 或 Share extension |

> 当前 target 为 iOS 26.0，因此 iOS 16/17/18 的 App Intents API 和 iOS 26 的 `supportedModes` 在文档层面可用；任何 iOS 27 符号都不能直接用于当前 target，除非产品明确决定提升 deployment target。

## 决策摘要

### 首批建议：3 个动作（均为普通 App Intent，不依赖 schema）

按优先级：

1. **查看今日剩余预算**（只读查询）——最贴合产品口号 “Know what you can spend today”，一句话就能得到答案，风险最低。
2. **记一笔支出**（写入）——最高频的记账动作，能从 Siri/Shortcuts 省去打开 App 和填表；需要明确“直接写入还是打开确认页”的产品决定。
3. **查看本周/本月支出**（只读查询）——复用现有 `StatsEngine`，适合周/月复盘；用两个 App Shortcut preset 避免短语参数化。

首批的普通路径依赖证据 **E1、E1a、E2–E8、E8a**：`AppIntent`、`AppIntent.title` / `description` / `parameterSummary`、`supportedModes` / `IntentModes`、`AppShortcutsProvider` / `AppShortcut`、`AppShortcutPhrase` / `applicationName`、`ProvidesDialog` / `ReturnsValue`、`IntentParameter`、`AppEnum` 及其 display representation 的文档可用性均已核对。首批不需要 `AppEntity`，不需要新增 target、entitlement 或 Info.plist key；全部逻辑仍在主 App target 内。构建、metadata 生成、Shortcuts 可见性和真机 Siri 运行均**未执行**。

### 可选 schema 增强

- **财务/预算/记账类没有匹配的 Apple schema domain**：截至 2026-10-26 的 Apple “App schema domains” 文档列出的 primary domains 为 audio、calendar、camera、clock、mail、maps、messages、notes、phone、photos、reminders、system / in-app search；另有 assistant、visualIntelligence 和若干 Shortcuts-specific domains（books、browser、files、journaling、presentation、reader、spreadsheet、whiteboard、word processor）。其中没有 finance、budget、expense、ledger 或 money 类 domain。因此首批 3 个动作不应为了“Apple Intelligence 支持”而强行套 schema。
- **`.system.open` / `.system.searchInApp` 属于 iOS 27**（`AppSchema.SystemIntent.open` / `searchInApp` 文档最低 27.0），当前 target 26.0 不可直接使用；它们也只适合“打开某个内容/在 App 内搜索”的导航动作，不适合创建支出或查询预算。由于本环境没有 Xcode 的 `AppIntentSchemas.sqlite`，这两个成员的精确必填参数/返回类型尚未核对，**标记 needs verification**，不进入首批。

### 阻塞性验证 / 就绪边界

- 首批 3 个普通路径的**必需符号证据齐全**（E1、E1a、E2–E8、E8a），没有因为缺少某个 API 声明而必须移出首批的项；它们保留在 ready ordinary path 中。
- 但以下都是**未执行的验证**，不能当作已通过：Xcode 编译与 `appintentsmetadataprocessor` metadata 生成；Shortcuts / Spotlight 实际列出；签名 iPhone 上 Siri 中文短语；后台/锁屏时 SQLite 访问；`AddExpenseIntent` 直接写入的产品确认与重复处理。
- App Shortcut 的 `\(.applicationName)` 短语 token 和 `AppShortcutPhrase` 的字符串插值 conform 已核对，但具体中文短语仍需编译和真机匹配；这不影响“普通 AppIntent 可在 Shortcuts 中运行”的符号判断。
- `.system.open` / `.system.searchInApp` 的精确参数/返回类型未核对，是**单独的 schema 验证缺口**，已从首批范围排除。

### 待验证 / 后续组

- **一句话记账草稿**（一句话 → 多笔草稿 → 用户确认）：业务已实现，但需要 foreground 路由和草稿页，且要把“本机规则优先 / 远端模型是否允许”的产品边界定清楚；成本 M，后续批次。
- **打开今天/账单页**：实现简单，但价值低于直接查询；需要 `TargetContentProvidingIntent` + `.onAppIntentExecution`，后续批次。
- **设置每日预算**：写入未来预算规则，需要确认与“追加规则而非编辑”的语义说明；后续批次。
- **删除账单**：破坏性动作，需要实体解析、确认、过期/已删除处理和恢复方案；标记 needs verification。
- **Spotlight 搜索账单**：需要 `IndexedEntity` / `indexAppEntities` 以及保存、删除、导入、清空时的索引维护；备注进入 Spotlight 还有隐私影响；标记 needs verification，成本 L。

### 需要产品决定的事项

1. “记一笔支出”Intent 是**直接写入账本**，还是只打开 `AddView` 让用户确认？直接写入更符合 Shortcuts 的自动化价值，但绕过了现有“草稿确认页”的人工确认；它不使用 AI，因此不违反 `docs/AI_PRIVACY.md` 的“AI 不得直接写入”规则，但仍是一个新的产品行为。
2. 没有填分类时，是否接受 `KeywordClassifier` 从备注推断、推断不出落到“其他”？这比默认“餐饮”更不猜测，但和 `AddView` 当前默认分类不同。
3. 预算/支出查询在 Siri 中的朗读/展示是否涉及隐私：当前 App 没有设备认证或 App 锁；是否对查询 Intent 使用 `authenticationPolicy = .requiresAuthentication` 需要产品决定（会要求设备认证，降低便利性）。
4. Siri 短语的语言/地区、App 名称 “Pace” 的发音，以及是否接受中文短语，必须在真机上验证；本文不假设任何地区配置。

## 评估的动作

### 查看今日剩余预算 — “今天还能花多少？”

- **业务状态：implemented。** `HomeView` 的 `budgetCard` / `noBudgetContent` 已经完整展示预算、已花、剩余或超支；数据来自共享核心，不依赖网络或 AI。
- **代码链：**
  - UI：`iosApp/iosApp/HomeView.swift` 的 `budgetCard(_:)`、`budgetContent(_:)`、`noBudgetContent(_:)`、`load()`、`refresh()`。
  - 业务：`iosApp/iosApp/PaceApp.swift` 的 `LedgerStore` 单例持有 `LedgerApi`；`HomeView` 调用 `LedgerStore.shared.api.todayOverview(todayIso:)`。
  - 共享核心：`shared/src/commonMain/kotlin/pace/shared/LedgerApi.kt` 的 `todayOverview(todayIso:)`；`shared/src/commonMain/kotlin/pace/shared/budget/BudgetEngine.kt` 的 `todayOverview`、`dailyOverview`、`netSpend`、`totalSpend`、`isOverspent`。
  - 数据：`allTransactions()` + `budgetHistory()`，SQLite `pace.db`；`TodayOverview` 定义在 `shared/src/commonMain/kotlin/pace/shared/model/Models.kt`。
  - 缺失链路：没有 Intent；没有对外暴露的只读查询入口，但业务函数已经是纯本地同步调用。
- **Verdict：recommended。** 这是最贴合产品核心价值的系统入口，且只读、无副作用、无需实体解析，适合作为第一个 Intent。
- **Direction（提案）：** 新增 `TodayBudgetIntent: AppIntent`，无参数（固定“今天”，避免日期/时区歧义）；`perform()` 调用 `LedgerStore.shared.api.todayOverview(todayIso: LedgerStore.shared.todayIso)`，返回 `some IntentResult & ProvidesDialog & ReturnsValue<String>`。
  - 结果文案建议：有预算且未超支 → “今天还能花 ¥X”；超支 → “今天已超支 ¥X”；没有预算 → “今天还没设置预算”。金额用现有 `Money.display` / `LedgerStore.format` 格式化，不自行拼小数。
  - 重复执行：纯查询，天然幂等；不改变账本。
  - 前台/后台：`supportedModes = .background`，不需要打开 App。
  - 歧义：无参数、无实体，不存在选择歧义。
- **Access and safety：**
  - 没有账号/登录，也没有按用户划分的数据权限；账本是单设备单账本。
  - 现有代码没有设备认证或 App 锁；查询结果通过 dialog 返回，Siri 可能朗读，可能被旁人听到。默认沿用现有行为（`alwaysAllowed`）；如果产品认为预算属于敏感信息，可提案 `authenticationPolicy = .requiresAuthentication`，但这是新行为，且会让每次 Siri 查询都要求设备认证。
  - 无破坏性效果、无确认需求、无恢复问题。
  - 后台读取 SQLite 在代码层面没有明显阻碍（`LedgerStore.shared` 是进程级单例，不依赖某个 View），但**设备锁定时数据库文件保护级别和首次解锁后的后台访问未验证**；需要在真机上确认。
- **Ordinary path：** `AppIntent` + `supportedModes = .background` + `ProvidesDialog` / `ReturnsValue` + 一个 `AppShortcut`。证据 E1、E2、E3、E4、E5、E6。没有 `AppEntity` 需求。
- **Schema enhancement：** 不适用。没有 finance/budget domain；`.system.open` / `.system.searchInApp` 是 iOS 27 的导航/搜索 schema，不是预算查询。证据 E12、E13。
- **System entry points：**
  - **Shortcuts**：Intent 会作为 App 的动作出现；`AppShortcutsProvider` 提供预配置 tile。
  - **Spotlight**：输入 App 名 “Pace” 时，App Shortcut tile 可被列出（不代表内容搜索）。
  - **Siri**：按参考指南，App Shortcut 短语应包含 `\(.applicationName)`；建议 “在 \(.applicationName) 查今天还能花多少”。Siri 语言/地区、真机可用性未验证。
  - **Apple Intelligence**：不声称支持；没有 schema，且当前 target 26.0。新 Siri 的 iOS 27 推理能力不属于本路径。
  - 小组件/控制项：没有 target；Action Button 可由用户把某个 App Shortcut 分配给侧边按钮，但本轮未评估、未验证。
- **Priority and cost：** 第 1 位；用户价值最高（核心问题、零输入）；入口收益高；就绪度高；风险低；成本 **S**（一个 Intent + 一个 shortcut，无实体）。假设 `LedgerStore` 可在 Intent 进程/后台安全初始化，需验证。
- **Validation and next step：** 代码与文档已确认业务函数和可用 API；**未编译、未运行**。下一步先在主 target 加 Intent 和 provider，确认 `appintentsmetadataprocessor` 能生成 metadata；再在 Shortcuts/Spotlight 看 tile；最后在签名 iPhone 上说中文短语验证 Siri。若后台锁屏访问失败，再考虑前台模式或要求解锁。

### 记一笔支出 — “午饭 28”

- **业务状态：implemented。** 手动记账、共享校验、重复检测和 SQLite 写入都已实现；一句话草稿确认最终也走同一个 `saveTransaction`。
- **代码链：**
  - UI：`iosApp/iosApp/AddView.swift` 的 `save(force:)`、`makeSaveInput(...)`；`iosApp/iosApp/FloatingAddButton.swift` 打开 `state.showAdd`；`DraftReviewView.saveAll()` 也走同一保存路径。
  - 共享核心：`shared/src/commonMain/kotlin/pace/shared/LedgerApi.kt` 的 `saveTransaction(input:)`，内部依次做 `Validators` 校验、`Money.parseToMinor`、日期/时区、分类校验、退款关联、`countInBudget` 归一化、`Ids.fingerprint` 重复检测、`insertTransactionRow`。
  - 数据：`Transaction`（`model/Models.kt`）有稳定 UUID `id`，持久化在 `pace.db`；`PaceApp.swift` 的 `LedgerStore` 是进程级单例。
  - 缺失链路：没有 Intent；直接写入是新的系统入口行为，但底层 `saveTransaction` 已具备完整校验。
- **Verdict：recommended（需产品确认直接写入）。** 这是最高频、最有自动化价值的动作；底层实现完整，风险主要集中在“系统入口直接写账本”的产品语义和重复处理。
- **Direction（提案）：** 新增 `AddExpenseIntent: AppIntent`。
  - 参数：`amount: Double`（必填，Siri 可追问），`note: String`（可选，默认空字符串）。首批不暴露分类/账户/日期，避免实体与日期时区复杂度。
  - 行为：把 `amount` 用固定 POSIX 格式转成两位小数字符串，再交给 `Money.shared.parseToMinor(text:)`；用 `KeywordClassifier.shared.suggestCategory(text:type:)` 得到分类（无命中为“其他”，不猜）；`type = TxnType.EXPENSE`、`localDate = LedgerStore.shared.todayIso`、`occurredAtEpochMillis = now`、`timezoneId = TimeZone.current.identifier`、`account = "现金"`、`currency = "CNY"`、`countInBudget = true`、`source = TxnSource.MANUAL`、`id = nil`、`refundOfId = nil`、`forceSave = false`，调用 `saveTransaction`。
  - 返回：成功时返回新账单 `id` 和一句 dialog（例如 “已记一笔：午饭 ¥28，餐饮”）；失败时返回用户能读懂的错误句。
  - 重复执行：每次成功调用都会新增一笔，**不是幂等**；这是“再记一笔”的预期语义，不是 toggle。
  - 重复检测：`saveTransaction` 在 `forceSave = false` 时遇到同指纹会返回 `DUPLICATE_FINGERPRINT`。提案：Intent **不**自动 `forceSave`，而是返回“今天已有一笔相同支出，请在 Pace 里确认后再记”，把最终决定留给用户。这是一个新的 Intent 侧 guard，依赖现有业务码，不改变共享核心。
  - 金额边界：`Money.parseToMinor` 拒绝 0、负数和超过 10^13 分的值；Intent 要把 null 转成自然语言错误，而不是入库。
  - 分类/账户：不做实体解析；首批不支持用户指定分类。用户可事后在 `AddView` 编辑。
- **Access and safety：**
  - 没有登录/账号；写入的是本机单一账本。
  - 直接写入需要产品确认：它不经过 `DraftReviewView`，但也没有使用 AI；`docs/AI_PRIVACY.md` 的“AI 不得直接写入”仍然成立。
  - 没有设备认证；如果 Siri 在锁屏可用，任何能唤醒 Siri 的人都能记一笔。是否要求 `authenticationPolicy = .requiresAuthentication` 需要产品决定；首批建议不加，保持低摩擦，但要在风险说明里写明。
  - 破坏性：否；恢复：用户可在账单页编辑或删除，删除后 8 秒内可撤销（`BillsView` 的 `delete` / `undoDelete`）。Intent 本身不提供撤销。
  - 敏感输出：dialog 可能读出备注/金额；这是用户主动说出的内容，风险相对低。
- **Ordinary path：** `AppIntent` + `supportedModes = .background` + `@Parameter`（Double/String）+ `ProvidesDialog` / `ReturnsValue` + `AppShortcut`。证据 E1、E2、E3、E4、E5、E6、E7。无 `AppEntity`。
- **Schema enhancement：** 不适用；没有 finance/expense domain。不能把“创建账单”映射到 `.system.open` 或 `.system.searchInApp`。证据 E12、E13。
- **System entry points：**
  - Shortcuts：可直接作为动作；`AppShortcut` 提供 “记一笔” tile。
  - Spotlight：App Shortcut tile 可出现；不是内容索引。
  - Siri：建议短语 “在 \(.applicationName) 记一笔”，预期由系统追问金额；该追问交互未验证。不要在首批使用金额参数化短语，减少未验证的短语语法与数字解析风险。
  - Apple Intelligence：不声称支持；无 schema。
- **Priority and cost：** 第 2 位；价值最高频；入口收益高；就绪度中高（金额转换、重复 guard、产品确认）；风险中；成本 **S/M**（一个 Intent、一个 shortcut、金额/重复测试）。假设 `Double` → 两位小数文本的转换使用 POSIX locale，避免小数点被本地化；假设 `KeywordClassifier` 在 Intent 进程可用（它是共享核心纯函数）。
- **Validation and next step：** 先写一个不依赖 UI 的保存测试（金额 28、28.5、0、负数、超上限；同一天同备注重复；备注为空分类为“其他”）；再在 App 内 debug 入口直接调用 `perform()` 验证写入；最后在签名 iPhone 上验证 Siri 追问金额与重复提示。**以上测试均未执行。**

### 查看本周 / 本月支出 — “这周花了多少？”

- **业务状态：implemented。** `StatsView` 已展示周/月总支出、预算内支出、退款、收入、超支天数和分类排行。
- **代码链：**
  - UI：`iosApp/iosApp/StatsView.swift` 的 `makeStats()`、`load()`、`refresh()`、`summaryCard(_:)`、`categoryCard(_:)`、`dailyCard(_:)`。
  - 共享核心：`LedgerApi.weekRange(todayIso:)`、`monthRange(todayIso:)`、`rangeStats(fromLocalDate:toLocalDate:)`；`shared/src/commonMain/kotlin/pace/shared/statistics/StatsEngine.kt` 的 `weekRange`、`monthRange`、`rangeStats`。
  - 数据：`RangeStats`（`totalExpenseAll`、`totalExpenseInBudget`、`refundTotal`、`incomeTotal`、`byCategory`、`daily`、`overspentDays`），全部由本地纯函数计算。
  - 缺失链路：没有 Intent；没有暴露周/月枚举，但 `StatsEngine` 已经按 localDate 计算。
- **Verdict：recommended。** 只读、现成逻辑、适合周/月复盘；参数只需一个固定枚举，不需要实体。
- **Direction（提案）：** 新增 `SpendingSummaryIntent: AppIntent`。
  - `enum SpendingPeriod: String, AppEnum`，case `week` / `month`；`typeDisplayRepresentation` 与 `caseDisplayRepresentations` 用中文（本周 / 本月）。
  - `@Parameter(title: "范围", default: .week) var period: SpendingPeriod`；提供自定义 `init(period:)` 以便两个 preset。
  - `perform()`：按 `period` 取 `weekRange` 或 `monthRange`，再调用 `rangeStats`；返回 dialog，例如 “本周支出 ¥X，其中预算内 ¥Y；花得最多的是餐饮 ¥Z”。没有数据时返回 “本周还没有支出”。
  - 统计口径：沿用 `totalExpenseAll`（全部支出，不减退款、不含转账）；不要把它说成“净支出”。如产品要“预算内支出”，用 `totalExpenseInBudget`，但要在文案里区分。
  - 重复执行：只读，幂等。
  - 前台/后台：`.background`。
- **Access and safety：** 同预算查询：无账号、无设备认证；结果通过 dialog 返回，Siri 可能朗读（未验证）；无破坏性；无恢复问题。后台 SQLite 锁屏行为未验证。
- **Ordinary path：** `AppIntent` + `AppEnum` + `@Parameter` + `.background` + `ProvidesDialog` / `ReturnsValue` + 两个 `AppShortcut` preset。证据 E1、E2、E3、E4、E5、E6、E7、E8。
- **Schema enhancement：** 不适用；没有 finance/statistics domain。证据 E12。
- **System entry points：**
  - Shortcuts：两个 preset tile（本周支出 / 本月支出）。
  - Spotlight：App Shortcut tile 可出现；不是账本内容搜索。
  - Siri：短语 “在 \(.applicationName) 查本周支出” / “查本月支出”；用 preset 避免在短语里放 `period` 参数。
  - Apple Intelligence：不声称支持。
- **Priority and cost：** 第 3 位；价值中高；入口收益中高；就绪度高；风险低；成本 **S**（枚举 + 两个 preset）。
- **Validation and next step：** 用现有 `StatsEngine` 的测试案例核对周/月边界（周一为周起点、自然月）；再验证无数据、只有收入/转账、只有退款等文案；**未执行**。

### 一句话记账草稿（后续，不进入首批）

- **业务状态：implemented。** `QuickAddView.submit()` 在未启用远端模型时调用 `LocalDrafts.parse` → `SentenceDraftParser.shared.parse`；启用后调用 `AiDraftClient.parse`；`DraftReviewView.saveAll()` 在用户确认后才调用 `saveTransaction`。
- **代码链：** `iosApp/iosApp/QuickAddView.swift`（`submit`、`runLocal`、`goManual`）→ `iosApp/iosApp/AiDraftClient.swift` 的 `LocalDrafts.parse` / `AiDraftClient.parse` → `shared/src/commonMain/kotlin/pace/shared/ai/SentenceDraftParser.kt`；UI 确认 → `DraftReviewView` → `LedgerApi.saveTransaction`。
- **Verdict：recommended（后续批次）。** 产品上很有辨识度，但需要 foreground 草稿页、`AppState` 路由和“是否允许远端模型”的边界；不适合和首批只读查询/简单写入混在一起。
- **Direction（提案）：** `PrepareDraftsIntent`，参数 `sentence: String`；默认只走 `SentenceDraftParser.shared`（本机、离线），解析后把 `[DraftItem]` 放入 `AppState.openDrafts` 并打开 `DraftReviewView`；返回草稿数量与“请在 Pace 里确认”。不直接写账本。重复执行会生成新的草稿集，不产生重复账单；草稿 `localId` 只在本次内存中有效，不需要持久化。缺金额时保持 `missingFields`，不要猜。
- **Access and safety：** 本地解析无网络；若使用 `AiDraftClient`，用户输入的整句话会发到用户配置的 OpenAI 兼容端点，必须有明确开关与隐私说明；首批建议只做本机规则。草稿页本身就是确认步骤。
- **Ordinary path：** `AppIntent` + `TargetContentProvidingIntent` + `.onAppIntentExecution` + `.foreground`；证据 E1、E2、E3、E4、E5、E9。`TargetContentProvidingIntent` / `.onAppIntentExecution` 最低 iOS 26.0。
- **Schema enhancement：** 不适用；没有 notes/journal 类 schema 能匹配“记账草稿”（不能为了套 schema 把账单伪装成笔记）。
- **System entry points：** Shortcuts/Siri 可调用，但会打开 App；Spotlight tile 可出现；Apple Intelligence 不声称支持。
- **Priority and cost：** 第 4 位；价值高；入口收益高；就绪度中；风险中（前台路由、草稿状态、远端隐私）；成本 **M**。
- **Validation and next step：** 先在 App 内 debug 入口调用 `perform()` 验证草稿页出现；再验证多笔、缺金额、空句子、已取消；最后真机 Siri。**未执行。**

### 打开今天 / 账单页（后续）

- **业务状态：implemented。** `RootView` 的 `TabView` 和 `AppState.tab` 已能切换首页/账单/统计/设置；`HomeView`、`BillsView` 已存在。
- **代码链：** `iosApp/iosApp/PaceApp.swift` 的 `AppTab`、`AppState`、`RootView`；`HomeView` / `BillsView`。
- **Verdict：recommended（后续批次）。** 导航价值低于直接查询；实现需要 `TargetContentProvidingIntent` 与 `.onAppIntentExecution`，但 API 已在 iOS 26 可用。
- **Direction（提案）：** `OpenTodayIntent` / `OpenBillsIntent`，无参数或仅枚举目标页；`.foreground`；通过 `.onAppIntentExecution` 设置 `AppState.tab` / 打开对应页面。重复执行安全。
- **Access and safety：** 无写入、无认证；只是把 App 带到前台。
- **Ordinary path：** E1、E2、E3、E4、E9。
- **Schema enhancement：** `.system.open` 是 iOS 27 的 `AppSchema.SystemIntent.open`，当前 target 不可用；精确参数/返回未核对，标记 needs verification。首批不采用。
- **System entry points：** Shortcuts/Siri/Spotlight；Apple Intelligence 不声称。
- **Priority and cost：** 第 5 位；成本 S/M；风险低。
- **Validation：** 编译 + App 内路由测试；未执行。

### 设置每日预算（后续）

- **业务状态：implemented。** `SettingsView.saveBudget()` 调用 `LedgerApi.setBudget(dailyAmountText:currency:effectiveFromIso:)`，追加一条预算规则；`BudgetEngine.budgetFor` 按 effectiveFrom 取最新规则。
- **代码链：** `iosApp/iosApp/SettingsView.swift` 的 `budgetSection`、`saveBudget`；`shared/.../LedgerApi.kt` 的 `setBudget`；`BudgetEngine.budgetFor`。
- **Verdict：recommended（后续批次）。** 改写未来预算，价值明确但频率低于查询/记账；需要确认与“追加规则、不重写历史”的语义。
- **Direction（提案）：** `SetDailyBudgetIntent`，参数 `amount: Double`，可选 `effectiveFrom` 默认为今天；调用 `setBudget`；返回“从 X 日起每日预算 ¥Y”。重复执行会追加多条规则；同一天多条时 `budgetFor` 取 `createdAtEpochMillis` 最新一条，历史规则保留。建议 `requestConfirmation`，因为会影响未来所有日子的预算；这是新的确认 guard。
- **Access and safety：** 写入；无认证；确认建议；恢复只能再追加一条规则（不能删除历史），需要在 dialog 里说明。
- **Ordinary path：** E1–E7、E10（`requestConfirmation`）。
- **Schema enhancement：** 不适用；无 finance domain。
- **System entry points：** Shortcuts/Siri；Apple Intelligence 不声称。
- **Priority and cost：** 第 6 位；成本 S/M；风险中。
- **Validation：** 预算生效日、同日多规则、非法金额、确认取消；未执行。

### 删除账单（needs verification）

- **业务状态：implemented。** `BillsView.delete` 调用 `LedgerApi.deleteTransaction(id:)`；`undoDelete` 用原数据 `saveTransaction` 恢复；删除后 8 秒撤销浮条（`BillsView` 的 `presentUndo` / `scheduleUndoDismiss`）。
- **代码链：** `BillsView.transactionList` / `txnRow` → `delete` → `LedgerApi.deleteTransaction`；`undoDelete` → `saveTransaction`。
- **Verdict：needs verification。** 业务存在，但系统入口删除需要实体解析、确认、过期/已删除处理，以及 Siri 场景下无法提供 8 秒撤销的方案；不能直接把 UI 的撤销假设搬到 Intent。
- **Direction（提案）：** `DeleteTransactionIntent`，参数 `transaction: TransactionEntity`（`AppEntity` + `EntityQuery`，按稳定 UUID 精确查找）；`requestConfirmation()`；删除后返回被删摘要。重复执行：第二次找不到 ID，应返回“这笔账单可能已删除”，不能假装成功。歧义策略：只按 ID 精确解析；搜索建议只列最近 10 笔，不做模糊匹配。
- **Access and safety：** 破坏性；确认必填；无认证；信息暴露（账单摘要）；恢复：Intent 本身不保证撤销，需产品决定是否提供“撤销上一次删除”或引导用户进 App。
- **Ordinary path：** E1–E4、E8（AppEntity/EntityQuery）、E10（确认）；需要新增实体和查询。
- **Schema enhancement：** 没有 delete finance domain；`.system.open` 不适用。
- **System entry points：** Shortcuts / Siri / Spotlight 均可作为动作入口；Apple Intelligence 不声称支持；删除确认在 Siri 上会以系统确认出现，但实际交互未验证。
- **Priority and cost：** 第 7 位；成本 M/L；风险高。
- **Validation and next step：** 实体 ID 跨重启、已删除 ID、重复删除、确认取消、锁屏；未执行。

### Spotlight / Siri 搜索账单（needs verification）

- **业务状态：implemented（搜索逻辑）。** `LedgerApi.searchTransactions(keyword:)` 在 `BillsView.loadTxns` 中用于搜索；但没有 AppEntity、没有 CoreSpotlight 索引。
- **代码链：** `BillsView` 的 `.searchable` → `loadTxns` → `searchTransactions`；未发现 `IndexedEntity` / `CSSearchableIndex` / `NSUserActivity`。
- **Verdict：needs verification。** 要实现“Spotlight 搜到我的账单/Shortcuts 选择账单”，需要实体、索引和生命周期维护；备注进入系统索引有隐私影响。
- **Direction（提案）：** `TransactionEntity: AppEntity` + `EntityStringQuery`（按备注/分类搜索，稳定 UUID）；`IndexedEntity` + `CSSearchableIndex.default().indexAppEntities` 在保存/导入后更新，删除时移除；`suggestedEntities()` 只返回最近/常用，<20。分类/账户如果需要参数，可再建 `CategoryEntity`。
- **Access and safety：** 账本备注可能包含敏感信息，进入 Spotlight 后可能被系统其他界面展示；需要产品明确是否只索引金额/分类/日期而排除备注，或完全不索引。无账号/认证。
- **Ordinary path：** E1–E4、E8、E11（`IndexedEntity`、`indexAppEntities`）。
- **Schema enhancement：** `.system.searchInApp` / `.system.open` 为 iOS 27；精确 required parameters/result 未核对（无 Xcode `AppIntentSchemas.sqlite`）；标记 needs verification，且当前 target 26.0 不使用。
- **System entry points：** Shortcuts / Siri / Spotlight（索引后）；Apple Intelligence 不声称支持；Spotlight 内容可见性受索引开关影响。
- **Priority and cost：** 第 8 位；成本 L；风险中高（隐私、索引一致性）。
- **Validation and next step：** 索引创建/删除/导入/清空、Spotlight 可见性、备注脱敏、真机；未执行。

### 导出 CSV / JSON（not recommended for Intents）

- **业务状态：implemented。** `SettingsView.exportCsv()` / `exportJson()` 生成临时文件并打开 `ShareSheet`；`LedgerApi.exportCsv` / `exportJson` 已实现。
- **代码链：** `SettingsView` 的 `transferSection`、`share(text:ext:)`、`ShareSheet`。
- **Verdict：not recommended。** 导出需要系统分享面板/文件交互，属于前台 UI 任务；从 Siri 触发会带来文件暴露和“导出到哪里”的歧义，且不是高频系统入口。若未来要支持自动化，应单独设计“生成文件并返回 URL”的 Shortcuts 动作，而不是复用分享面板。
- **Direction（提案边界）：** 首批不提案 Intent；若未来要做，只能生成临时文件并返回 URL，由用户或 Shortcuts 决定保存位置，不自动上传。
- **Access and safety：** 导出包含完整账本，隐私敏感；无认证；文件一旦交给 iCloud/Drive/微信由外部服务管理（`SettingsView` footer 已说明）。
- **Ordinary path：** 不适用（不提案）。
- **Schema enhancement：** 无匹配 domain；`.system.open` 不适用。
- **System entry points：** Shortcuts 可作为未来的文件生成动作；Siri 不推荐；Apple Intelligence 不声称。
- **Priority and cost：** 低系统入口价值；成本 M/L（文件生命周期、分享、隐私）；风险高。
- **Validation and next step：** 不执行；若未来提案，先验证临时文件清理和分享失败路径。

### 导入 / 恢复 / 清空账本（not recommended）

- **业务状态：implemented。** `SettingsView` 的 `fileImporter`、`previewImport`、`applyImport(mode:)`、`clearAllData()`；`LedgerApi` 有事务性导入和清空。
- **Verdict：not recommended。** 文件选择、预览、REPLACE 确认和清空都属于高风险、强 UI 的操作；不适合 Shortcuts/Siri 自动化，误触发代价高。
- **Direction（提案边界）：** 不提案 Intent；继续留在 `SettingsView` 的显式 UI 流程。
- **Access and safety：** 破坏性/覆盖性；需要多次确认；无认证；恢复依赖导出文件。现有 `SettingsView` 已有二次确认，Intent 不应绕过。
- **Ordinary path：** 不适用（不提案）。
- **Schema enhancement：** 无。
- **System entry points：** 不建议暴露到 Shortcuts/Siri/Apple Intelligence。
- **Priority and cost：** 不进入优先级；成本高、风险高。
- **Validation and next step：** 不执行；保持现有 UI 验证。

### AI 设置 / 测试连接（excluded）

- **业务状态：implemented。** `QuickAddSettingsView` 的开关、endpoint/model/key、`AiDraftClient.testConnection`；Key 存 Keychain。
- **Verdict：not recommended。** 这是配置操作，不是用户任务；通过 Siri 修改 API Key 还会带来密钥暴露风险。只保留在 App 内设置页。
- **Direction（提案边界）：** 不提案 Intent；API Key 继续只存在 Keychain。
- **Access and safety：** 配置写入；Keychain 存储；无账号；不应在系统入口朗读或显示密钥。
- **Ordinary path：** 不适用（不提案）。
- **Schema enhancement：** 无。
- **System entry points：** 无；不暴露到 Shortcuts/Siri/Apple Intelligence。
- **Priority and cost：** 不进入优先级。
- **Validation and next step：** 不执行。

### 分类管理 / 小部件 / 控制中心 / 分享扩展（planned / insufficient evidence）

- **分类管理：** `LedgerApi.addCategory(name:kind:)` 已实现，但 iOS 没有分类管理 UI；`AddView` 只读取 `categories()`。属于 planned/未暴露。
- **WidgetKit、Control widget、Share extension：** 工程没有这些 target；`PLAN.md` 只把它们列为 iOS 平台增强方向。属于 planned，不在本次首批。
- **通知/后台刷新：** 未发现 `UserNotifications` 或 `BackgroundTasks` 实现；不属于 App Intents 首批。

## API 与可用性证据

> 说明：以下最低 OS 来自 2026-10-26 读取的 Apple 在线符号文档。本环境没有 Xcode/iPhoneOS SDK，**没有读取所选 SDK 的 Swift interface 或 `AppIntentSchemas.sqlite`，也没有编译**；因此“文档可用”不等于“本项目已编译通过”。项目 deployment target 为 iOS 26.0，iOS 16/17/18/26 的符号在文档层面覆盖当前 target；27 的符号不覆盖。所有 URL 均为 `https://developer.apple.com/documentation/...`。

| ID | 精确符号 / domain.member | 最低 OS | 所需 SDK/工具链与所选 SDK 证据 | 适用面 / 条件 | 来源 URL 或 SDK 路径/声明 | 验证日期 / 快照日期 | 缺口与下一步 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| E1 | `AppIntent`（protocol） | iOS 16.0 | 文档声明；项目 target 26.0；需要包含 iOS 26 SDK 的 Xcode，本环境未读取 SDK | Shortcuts / Spotlight / Siri 的动作基础 | `documentation/appintents/appintent` | 2026-10-26 | 未编译；下一步 `xcodebuild` 或 Xcode build |
| E1a | `AppIntent.title`、`AppIntent.description`、`AppIntent.parameterSummary` | iOS 16.0 | 文档声明 | Intent 标题/描述/参数摘要，Shortcuts 和 metadata 使用 | `documentation/appintents/appintent/title`、`.../appintent/description`、`.../appintent/parametersummary` | 2026-10-26 | 中文本地化与 build-time metadata 未验证 |
| E2 | `AppIntent.supportedModes`、`IntentModes`、`IntentModes.background` / `.foreground` | iOS 26.0 | 文档声明；target 26.0 覆盖 | 选择后台/前台执行 | `documentation/appintents/appintent/supportedmodes`、`.../intentmodes`、`.../intentmodes/background` | 2026-10-26 | 未验证后台在锁屏/未解锁时的实际行为 |
| E3 | `AppShortcutsProvider`、`AppShortcutsProvider.appShortcuts` | iOS 16.0 | 文档声明 | 参考指南：一个 App 使用一个 provider；App Shortcut 注册 | `documentation/appintents/appshortcutsprovider`、`.../appshortcutsprovider/appshortcuts` | 2026-10-26 | 未编译；provider 与 metadata 生成待验证 |
| E4 | `AppShortcut`（struct）；`init(intent:phrases:shortTitle:systemImageName:)` | struct iOS 16.0；该 init **iOS 17.0** | 文档声明；target 26.0 覆盖 | Shortcuts/Spotlight tile、Siri 短语 | `documentation/appintents/appshortcut`、`.../appshortcut/init(intent:phrases:shorttitle:systemimagename:)-8yntq` | 2026-10-26 | 短语/标题本地化与 tile 颜色未验证 |
| E5 | `AppShortcutPhrase`、`AppShortcutPhraseToken.applicationName`、`ExpressibleByStringInterpolation` | iOS 16.0 | 文档声明；`AppShortcutPhrase` 的 Conforms To 列出 `ExpressibleByStringInterpolation` | 参考指南要求 Siri / Spotlight 短语含 App 名 token | `documentation/appintents/appshortcutphrase`、`.../appshortcutphrasetoken/applicationname` | 2026-10-26 | `\(.applicationName)` 的实际编译与 Siri 匹配需真机验证；中文短语/地区未验证 |
| E6 | `ProvidesDialog`、`ReturnsValue`、`IntentResult` | iOS 16.0 | 文档声明 | 返回 dialog 和值 | `documentation/appintents/providesdialog`、`.../returnsvalue`、`.../intentresult` | 2026-10-26 | dialog 文案/本地化未编译 |
| E7 | `IntentParameter`、`IntentParameter` 的 Double/String 初始化 | iOS 16.0 | 文档声明；`@Parameter` 由 `IntentParameter` 支持 | 金额/备注参数 | `documentation/appintents/intentparameter`、`.../intentparameter/init(title:description:default:controlstyle:inclusiverange:requestvaluedialog:inputconnectionbehavior:)-4mc52` | 2026-10-26 | `Double` → 两位小数文本的本地化转换需测试 |
| E8 | `AppEnum`、`AppEntity`、`EntityQuery`、`EntityStringQuery`、`StaticDisplayRepresentable` | iOS 16.0 | 文档声明 | 周/月枚举；后续实体/查询 | `documentation/appintents/appenum`、`.../appentity`、`.../entityquery`、`.../entitystringquery`、`.../staticdisplayrepresentable` | 2026-10-26 | 实体/查询只在后续动作使用；未编译 |
| E8a | `TypeDisplayRepresentable.typeDisplayRepresentation`、`CaseDisplayRepresentable.caseDisplayRepresentations` | iOS 16.0 | 文档声明 | `AppEnum` 的中文类型名与 case 展示 | `documentation/appintents/typedisplayrepresentable/typedisplayrepresentation`、`.../casedisplayrepresentable/casedisplayrepresentations` | 2026-10-26 | 中文展示未编译；需要 `AppEnum` 一致实现 |
| E9 | `TargetContentProvidingIntent`、`View.onAppIntentExecution(_:perform:)` | iOS 26.0 | 文档声明；target 26.0 覆盖 | 前台打开草稿页/账单页 | `documentation/appintents/targetcontentprovidingintent`、`documentation/swiftui/view/onappintentexecution(_:perform:)` | 2026-10-26 | 前台路由未验证；必须在 `@MainActor` UI 中处理 |
| E10 | `AppIntent.requestConfirmation()`、`IntentAuthenticationPolicy` | iOS 16.0 | 文档声明 | 删除/预算等敏感动作确认；可选设备认证 | `documentation/appintents/appintent/requestconfirmation()`、`.../intentauthenticationpolicy` | 2026-10-26 | 确认/认证交互未在 Shortcuts/Siri 真机验证 |
| E11 | `IndexedEntity`、`CSSearchableIndex.indexAppEntities(_:priority:)` | iOS 18.0 | 文档声明；target 26.0 覆盖 | Spotlight 内容索引（后续搜索动作） | `documentation/appintents/indexedentity`、`documentation/corespotlight/cssearchableindex/indexappentities(_:priority:)` | 2026-10-26 | 索引生命周期、隐私、删除/导入同步未验证 |
| E12 | `AppIntent(schema:)` 宏；App schema domains | 宏 iOS 18.0；domain 最低见各自页面 | 文档声明；本环境未读取 schema DB | 采用 Apple 预定义 schema | `documentation/appintents/appintent(schema:)`、`documentation/appintents/app-schema-domains` | 2026-10-26 | 域清单无 finance/budget；页面的域列表随系统版本可能变化，需在实现时复核 |
| E13 | `AppSchema.SystemIntent.open`、`AppSchema.SystemIntent.searchInApp` | **iOS 27.0** | 文档声明；当前 target 26.0 **不可直接使用**；需要 iOS 27 SDK/Xcode 27 和 target bump | iOS 27 的打开内容/App 内搜索 schema | `documentation/appintents/appschema/systemintent/open`、`.../searchinapp` | 2026-10-26 | 精确 required parameters/result 未读取（无 `AppIntentSchemas.sqlite`）；标记 needs verification，不进首批 |

补充：`AppShortcut` 的 `init(intent:phrases:shortTitle:systemImageName:)` 文档最低 iOS 17.0，不是 16.0；本项目的 26.0 target 覆盖它，但不能把这个 init 当成 iOS 16 可用。`AppShortcutPhraseToken.applicationName` 和 `AppShortcutPhrase` 的字符串插值一致性已核对；具体中文短语仍要编译和真机验证。

## 计划中、不确定与被排除的功能

| 功能 / 用户任务 | 业务状态与证据 | Verdict 与排除/延后原因 | 什么会改变决定 |
| --- | --- | --- | --- |
| 一句话记账草稿 | implemented：`QuickAddView` → `SentenceDraftParser` / `AiDraftClient` → `DraftReviewView` → `saveTransaction` | 后续批次；需要 foreground 草稿页和“远端模型是否允许”的产品决定，不进首批 | 产品确认只做本机规则、接受打开 App 确认；完成 `TargetContentProvidingIntent` 路由 |
| 打开今天/账单页 | implemented：`RootView` + `AppState.tab` | 后续；价值低于查询；需要 foreground 路由 | 用户明确要“打开 App 到某页”的 Siri 入口 |
| 设置每日预算 | implemented：`SettingsView.saveBudget` → `LedgerApi.setBudget` | 后续；影响未来预算，需要确认与追加规则说明 | 产品接受预算修改需确认；完成金额/生效日测试 |
| 删除账单 | implemented：`BillsView.delete` / `undoDelete` | needs verification；破坏性、实体解析、无 Siri 撤销方案 | 产品定义删除确认、过期 ID 和恢复策略 |
| Spotlight / Siri 搜索账单 | 搜索逻辑 implemented：`LedgerApi.searchTransactions`；无索引 | needs verification；需要 AppEntity + `IndexedEntity`，备注隐私待定 | 产品决定索引哪些字段、是否允许备注进入 Spotlight |
| 导出 CSV / JSON | implemented：`SettingsView` + `ShareSheet` | not recommended；前台文件分享、隐私、非高频系统入口 | 若要做自动化导出，需单独设计返回文件 URL 的 Shortcuts 动作 |
| 导入 / 恢复 / 清空 | implemented：`SettingsView` + `LedgerApi.applyImport` / `clearAllData` | not recommended；高风险、强 UI、需多次确认 | 不应通过 Siri 自动化；保持 App 内操作 |
| AI 设置 / 测试连接 | implemented：`QuickAddSettingsView` / `AiDraftClient.testConnection` | excluded；配置操作，不是用户任务；密钥暴露风险 | 不改变，保留在设置页 |
| 分类管理 | `LedgerApi.addCategory` 已实现；iOS 无管理 UI | planned / insufficient evidence；不属于首批 | 先补设置 UI，再考虑 Intent |
| WidgetKit / Control widget / Share extension | 无 target、无源码；`PLAN.md` 仅列为方向 | planned；不在 App Intents 首批范围 | 产品排期新增扩展 target 后单独评估 |
| 通知 / 后台刷新 | 未发现实现 | planned / insufficient evidence；不属于首批 | 需要先实现通知/后台任务 |

## 产品交接

- **首批提案：** 3 个普通 App Intent（3 个 intent、4 个 App Shortcut tile）：
  1. `TodayBudgetIntent` — 查今天还能花多少。
  2. `AddExpenseIntent` — 记一笔支出（金额 + 可选备注）。
  3. `SpendingSummaryIntent` — 本周/本月支出（两个 preset）。
- **实现前依赖 / 验证：**
  - 在主 App target 新增一个 `AppShortcutsProvider`；不要新增 Intents extension、entitlement 或 Info.plist key（App Intents 主 target 即可）。
  - 当前 `project.yml` 设置 `CODE_SIGNING_ALLOWED: NO`，没有 Team ID；真机验证需在本地 Xcode 临时配置签名，不要改仓库中的工程配置。
  - 构建前先生成缺失的 `shared.xcframework`（`./gradlew :shared:assembleSharedReleaseXCFramework`）并运行 `xcodegen generate`；当前仓库没有 `.xcodeproj` 或已构建的 XCFramework。
  - 用包含 iOS 26 SDK 的 Xcode 编译，确认 `appintentsmetadataprocessor` 成功、Shortcuts 出现 tile；本环境无法执行。
  - 用 App 内 debug 入口直接调用 `perform()` 验证写入/查询副作用；再在签名 iPhone 上验证 Shortcuts/Spotlight 运行、Siri 中文短语、后台锁屏行为。
  - 产品先决定“直接写入 vs 打开 AddView 确认”、空备注分类策略、是否要求设备认证。
  - 首批不采用 Apple Intelligence schema；`.system.open` / `.searchInApp` 是 iOS 27，精确参数/返回未核对，保持 needs verification。
- **后续可选：** 一句话草稿、打开页面、设置预算、删除、Spotlight 搜索；分别需要 foreground 路由、实体/确认、索引与隐私设计。
- **证据边界：** 本次只读取代码和 Apple 在线文档；没有修改任何 App 代码、工程配置、entitlement 或 deployment target；没有构建、没有运行 Simulator/真机、没有执行任何账本写入或删除等业务操作。报告只新增了本文件 `intent-opportunities.md`。
- **最需要补的证据：** (1) 实际 Xcode/SDK 编译与 `AppShortcutsProvider` metadata 生成；(2) 签名设备上中文 Siri 短语和 Shortcuts/Spotlight 实际运行；(3) `AddExpenseIntent` 直接写入的产品确认与重复处理测试；(4) 后台/锁屏时 SQLite 数据保护行为；(5) 若未来采用 iOS 27 `.system.*` schema，读取 `AppIntentSchemas.sqlite` 核对精确参数/返回类型。
