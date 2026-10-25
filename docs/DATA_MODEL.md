# Pace 数据模型与枚举（v1）

本文档定义跨端共享的数据字段与枚举。`shared/transaction`、`shared/money`、`shared/date-time` 按 此文档实现；数据库表结构与 JSON 导出字段一一对应（JSON 格式见 `EXPORT_FORMAT.md`）。

## 1. 金额

- 所有金额在内部保存为**最小货币单位的 `Long`**（人民币为「分」），禁止使用浮点类型保存或计算金额。
- `currency` 使用 ISO 4217 字母码（如 `CNY`），第一版只做记账货币标识，不换算汇率。
- 展示层格式化规则：`amountMinor / 100` 保留两位小数；千分位由各平台自行处理，但必须由整数运算产生。
- 校验：`amountMinor > 0` 且 `<= 10^13`；输入层的小数金额先转最小单位再入库。

## 2. 账单（Transaction）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | String | 稳定唯一 ID，UUID v4，由共享核心生成；导入时保留原值 |
| `type` | String 枚举 | `EXPENSE` / `INCOME` / `REFUND` / `TRANSFER` |
| `amountMinor` | Long | 最小货币单位金额，恒为正数；方向由 `type` 决定 |
| `currency` | String | ISO 4217，默认 `CNY` |
| `category` | String | 分类名，必须是分类表中的有效分类 |
| `account` | String | 账户/支付方式名，默认「现金」 |
| `note` | String | 备注，可为空字符串，长度 `<= 500` |
| `occurredAtEpochMillis` | Long | 发生时间（UTC 毫秒），用于同日内排序 |
| `localDate` | String | 归属日 `yyyy-MM-dd`，按发生时的用户时区折算；预算与统计一律使用此字段 |
| `timezoneId` | String | 记账时的 IANA 时区，如 `Asia/Shanghai`，随账单快照保存 |
| `countInBudget` | Boolean | 是否计入每日预算；INCOME/TRANSFER 恒为 false |
| `refundOfId` | String? | 仅 REFUND：关联的原账单 id |
| `source` | String 枚举 | `MANUAL` / `IMPORT` / `AI_DRAFT`（来源标记，不影响计算） |
| `fingerprint` | String | 重复检测指纹，见第 5 节 |
| `createdAtEpochMillis` | Long | 创建时间 |
| `updatedAtEpochMillis` | Long | 最后修改时间 |

### 2.1 类型枚举语义

- `EXPENSE` 支出；`INCOME` 收入；`REFUND` 退款（冲减支出）；`TRANSFER` 转账/还款（资金移动，不是消费）。
- `REFUND` 必须带 `refundOfId` 且指向一笔存在的 `EXPENSE`；退款金额可小于原账单（部分退款）。
- `TRANSFER` 不计入任何统计支出；账户字段表达资金去向时可写入 `note`。
- 编辑账单时不允许修改 `type` 之外的历史指纹冲突由共享核心重新计算 `fingerprint`。

## 3. 分类（Category）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | String | UUID |
| `name` | String | 唯一名称，长度 1..20 |
| `kind` | String 枚举 | `EXPENSE` / `INCOME` / `TRANSFER` |
| `sortOrder` | Int | 排序序号，越小越靠前 |
| `usageCount` | Long | 使用次数（最近使用排序用） |

默认分类（order 依序）：餐饮、交通、购物、住房、娱乐、医疗、教育、人情社交（EXPENSE 类）；工资、理财（INCOME 类）；转账（TRANSFER 类）；「其他」不可删除。

## 4. 预算规则（BudgetRule）

字段与生效规则见 `BUDGET_RULES.md` 第 4 节。表结构：

| 字段 | 类型 |
| --- | --- |
| `id` | String |
| `dailyAmountMinor` | Long |
| `currency` | String |
| `effectiveFromLocalDate` | String（yyyy-MM-dd） |
| `createdAtEpochMillis` | Long |

## 5. 指纹（fingerprint）

用于导入去重与重复入账检测。指纹是以下字段规范化拼接后的 FNV-1a 64 位哈希（十六进制字符串，前缀 `fp1_`）：

```
v1|type|amountMinor|currency|localDate|category|account|note
```

- 指纹**不包含**秒级时间戳（`occurredAtEpochMillis`）：同一天、同类型、同金额、同分类、同账户、同备注的两笔账单指纹相同。这使得「双击确认」与「重复导入」可以被稳定识别。
- 指纹在两端、任何语言实现下必须一致（纯整数/字符串哈希，无平台差异）。
- 新增账单时若库中已存在相同指纹的其他账单，共享核心返回 `DUPLICATE_FINGERPRINT` 业务码；用户明确选择「仍然保存」时以 `forceSave = true` 重试，允许真实的重复消费入账。

## 6. 时间与归属日

- 记账时：`occurredAt`（Instant）+ 用户当前时区 → `localDate`，随账单保存 `timezoneId`。
- 预算、统计、账单列表分组一律使用 `localDate`，不使用设备当前时区重算历史账单。
- 「今天」由调用方按用户当前时区计算后传入共享核心（`yyyy-MM-dd` 字符串），共享核心自身不读取系统时间做业务判断（时间戳生成除外，经 `Clock` 注入可测试）。
- 本周定义：周一为第一天；本月定义：自然月，均按 `localDate` 字符串前缀比较即可（`yyyy-MM`）。

## 7. 错误码

共享校验（`shared/validation`）返回的业务错误码，两端必须原样展示对应文案：

| 错误码 | 场景 |
| --- | --- |
| `INVALID_AMOUNT` | 金额 <= 0、超过上限或非数字 |
| `INVALID_TYPE` | 未知账单类型 |
| `INVALID_CATEGORY` | 分类不存在或为空 |
| `INVALID_DATE` | localDate 格式错误或超出 1970-01-01..2100-12-31 |
| `INVALID_TIMEZONE` | 时区 ID 非法 |
| `REFUND_MISSING_ORIGINAL` | 退款缺少 refundOfId |
| `REFUND_ORIGINAL_NOT_FOUND` | refundOfId 指向的账单不存在或不是 EXPENSE |
| `NOTE_TOO_LONG` | 备注超过 500 字符 |
| `DUPLICATE_FINGERPRINT` | 同指纹账单已存在（可用 forceSave 明确覆盖） |
| `DUPLICATE_ID` | 导入时文件内 id 重复 |
| `NOT_FOUND` | 预留（当前编辑不存在 id 按 upsert 恢复，用于撤销流程） |
| `IMPORT_FORMAT_VERSION` | 导入文件版本不支持 |
| `IMPORT_MALFORMED_JSON` | JSON 语法错误或非 Pace 信封 |
| `IMPORT_VALIDATION_FAILED` | 导入文件整体校验失败（附明细） |

## 8. AI 草稿（预留）

AI 草稿不是账单，只是「待确认输入」。草稿结构（阶段 3 实现，格式见 `AI_PRIVACY.md`）与账单字段保持同名同义，未确认前不进入账单表；确认后按普通账单走同一校验与入账路径。
