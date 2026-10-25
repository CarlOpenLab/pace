# Pace 导出与导入格式（v1）

本文档定义 CSV/JSON 导出与 JSON 恢复的跨端契约。实现位于 `shared/export` 与 `shared/import`，两端共享，禁止客户端各自实现。

## 1. 通用规则

- 导出完全在本地生成，不经过网络；用户通过系统分享面板/文件选择器自行保存。
- 导出文件名：`pace-ledger-YYYYMMDD-HHmmss.csv` / `.json`。
- 金额一律导出**最小货币单位整数**（分）；CSV 中额外提供十进制展示列（由整数运算产生）。
- 导出包含全部账单、分类、预算规则（含历史规则）；不包含任何设备标识或用户身份信息。

## 2. JSON 导出格式

顶层信封：

```json
{
  "formatVersion": 1,
  "app": "pace",
  "exportedAtEpochMillis": 1790000000000,
  "timezone": "Asia/Shanghai",
  "defaultCurrency": "CNY",
  "transactions": [],
  "categories": [],
  "budgetRules": []
}
```

- `formatVersion` 当前为 `1`。读取方遇到更大版本必须拒绝并返回 `IMPORT_FORMAT_VERSION`。
- `transactions`、`categories`、`budgetRules` 的字段与 `DATA_MODEL.md` 完全一致，字段名使用 camelCase。

transactions 数组元素示例：

```json
{
  "id": "6f9619ff-8b86-d011-b42d-00cf4fc964ff",
  "type": "EXPENSE",
  "amountMinor": 2800,
  "currency": "CNY",
  "category": "餐饮",
  "account": "微信支付",
  "note": "午饭",
  "occurredAtEpochMillis": 1790000000000,
  "localDate": "2026-10-25",
  "timezoneId": "Asia/Shanghai",
  "countInBudget": true,
  "refundOfId": null,
  "source": "MANUAL",
  "fingerprint": "fp1_1a2b3c4d5e6f7890",
  "createdAtEpochMillis": 1790000000000,
  "updatedAtEpochMillis": 1790000000000
}
```

## 3. CSV 导出格式

- UTF-8，第一行表头，CRLF 或 LF 均可（写入用 LF），字段含逗号/引号/换行时按 RFC 4180 双引号转义。
- 表头固定为：

```
id,date,time,type,amount,currency,category,account,note,count_in_budget,refund_of_id
```

- `date` = `localDate`；`time` = 发生时间的 `HHmmss`（按账单保存的 `timezoneId` 还原，不按导出设备时区）。
- `type` 大写枚举；`amount` 为十进制展示（两位小数）；`count_in_budget` 为 `true/false`；空值导出空串。
- CSV 定位是「查看与交换」，**不承诺**恢复预算关联等完整信息；恢复一律走 JSON。

## 4. JSON 导入（恢复）

### 4.1 流程

1. 读取文件全文，先做**整体结构校验**（信封、版本、每条记录字段）。
2. 校验通过后生成本地预览（不写库）：账单数、日期范围、预算设置摘要、与现有账本的重复数。
3. 用户在「合并到现有账本」与「替换当前账本」之间选择；替换必须二次确认。
4. 写入在一个数据库事务内完成；任何一条失败则整体回滚，现有账本保持不变。

### 4.2 预览（ImportPreview）

```
ImportPreview(
  transactionCount, categoryCount, budgetRuleCount,
  firstLocalDate, lastLocalDate,
  duplicateCount,          // id 已存在或指纹与现有账单相同的条数
  valid: Boolean, errors: List<String>   // 校验失败明细（不包含完整备注内容）
)
```

### 4.3 合并（MERGE）规则

- 导入记录 `id` 与现有账单相同 → 视为重复，**跳过**（现有账单优先，不覆盖用户后续编辑）。
- `id` 不同但 `fingerprint` 与现有账单相同 → 视为重复，跳过。
- `id` 与指纹都不同 → 插入。
- 分类与预算规则按 `id`/名称去重后追加；导入的预算规则生效日早于现有规则时保留在历史中，不改变当前预算（当前预算 = 生效日最新的规则）。

### 4.4 替换（REPLACE）规则

- 事务内清空 transactions、budget_rules、categories 后整体写入导入内容。
- 失败回滚后原账本必须逐字节不变（含排序与使用计数）。

### 4.5 校验明细

- 逐条校验 `DATA_MODEL.md` 第 7 节错误码；文件中任何一条非法即整体 `valid = false`，禁止部分写入。
- 时间戳字段非法（负数或超过 2100 年）按 `INVALID_DATE` 处理。

## 5. 验收案例

| # | 场景 | 期望 |
| --- | --- | --- |
| E1 | 导出→新环境恢复（REPLACE） | 账单、分类、预算规则与统计结果完全一致 |
| E2 | 同一 JSON 导入两次（MERGE） | 第二次 duplicateCount = 全部，账本不变 |
| E3 | 手工篡改金额为负数 | 预览 valid=false，含 INVALID_AMOUNT，未写库 |
| E4 | formatVersion = 99 | 拒绝，IMPORT_FORMAT_VERSION |
| E5 | 导出 CSV 用 Excel 打开 | 中文不乱码（UTF-8），金额两位小数 |
| E6 | 导入文件 JSON 语法错误 | 明确报错，不崩溃，账本不变 |
