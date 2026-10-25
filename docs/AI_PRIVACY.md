# Pace AI 隐私规范与草稿协议（v1）

本文档冻结 AI 的数据边界与草稿协议。阶段 3 之前，客户端只实现「隐私与 AI 设置」页中的模式开关与说明，不接入任何远端模型。

## 1. 数据边界（必须遵守）

- AI **默认关闭**。账本的全部能力（记账、编辑、预算、统计、导出、恢复）在 AI 关闭时完整可用。
- 账本事实只存在于设备本地数据库；任何 AI 功能不得绕过用户确认直接写入、修改或删除账单。
- **本地隐私模式**（默认）：账本内容不离开设备。仅允许本地规则解析（关键词分类）。
- **AI 辅助模式**：用户主动开启后，一次请求只发送完成当前任务所需的最小内容（用户当次输入的文本或选定的单条信息）；禁止发送完整账本历史、分类统计全文或数据库内容。
- 开启 AI 辅助模式前必须展示一次性说明：当前输入可能离开设备；第三方模型服务的处理规则由其服务条款决定。
- 日志与埋点不得记录完整消费内容、备注、票据内容或任何密钥。

## 2. 首发能力：自然语言生成待确认草稿

固定流程：

```
用户输入文本 →（远端 GLM 或本地回退）解析 → 本地业务校验 → 待确认草稿 → 用户逐笔确认 → 本地正式入账
```

- 金额、日期、类型、分摊不明确时，草稿标记「需要补充」，禁止猜测定稿。
- AI 超时、失败或返回格式错误 → 回退手动记账，不阻塞任何本地功能。
- 确认按钮具备防重：同一草稿重复确认不得产生重复账单（入库前指纹查重兜底）。

## 3. 草稿协议 JSON Schema（v1）

AI Provider 返回内容先解析为以下版本化结构，再进入本地校验：

```json
{
  "draftVersion": 1,
  "drafts": [
    {
      "localId": "d-001",
      "type": "EXPENSE",
      "amountText": "28",
      "amountMinor": 2800,
      "currency": "CNY",
      "dateText": "昨天",
      "localDate": "2026-10-25",
      "category": "餐饮",
      "note": "午饭",
      "account": null,
      "countInBudget": true,
      "missingFields": [],
      "confidence": 0.82
    }
  ],
  "parseErrors": []
}
```

字段规则：

- `missingFields` 取值：`AMOUNT` / `DATE` / `TYPE` / `CATEGORY`；非空时该草稿必须停留在「需要补充」状态，用户补齐前确认按钮禁用。
- `amountMinor` 由本地从 `amountText` 解析并校验，不信任模型给出的数值直接入库。
- `localDate` 为空或无法解析 → 归入 `missingFields`，默认填今天但不自动确认。
- `confidence` 仅用于 UI 提示，不影响校验结果。
- `parseErrors` 记录解析失败原因（枚举码），不包含原始用户输入全文。

## 4. Provider 接口

```
interface AiDraftProvider {
  fun parse(input: UserTextInput): DraftResult
}
```

- 实现可替换：`LocalFallbackProvider`（本地规则，纯离线）与 `GlmProvider`（阶段 3 接入）。
- 模型密钥、地址、模型名不得硬编码进客户端；GLM 密钥由受控服务端或用户明确配置的本地代理管理。
- 若用户选择「任何账本内容都不能离开设备」，则 `GlmProvider` 不可用，只能使用 `LocalFallbackProvider`。
- 现有 Web 原型中的 AI 分类接口（`src/lib/ai.ts`）按此规范降级：不再默认把账单字段发给外部接口；API Key 不进入原生客户端。

## 5. 草稿错误码

| 错误码 | 场景 |
| --- | --- |
| `AI_DISABLED` | AI 模式未开启 |
| `AI_TIMEOUT` | 请求超时（本地回退手动记账） |
| `AI_PARSE_FAILED` | 模型返回无法解析为草稿协议 |
| `AI_REJECTED` | 模型拒答或返回空草稿 |
| `DRAFT_VALIDATION_FAILED` | 草稿未通过本地业务校验（附 DATA_MODEL 错误码） |

## 6. 设置页要求（阶段 1 即上线）

隐私与 AI 设置页必须包含：

1. 模式开关：本地隐私模式（默认）/ AI 辅助模式，附数据流向说明文案。
2. 「AI 从不直接修改账本」的固定说明。
3. 数据删除入口（清空全部账单，二次确认）。
4. 导出提示：文件一旦交给 iCloud/Drive/微信等外部服务，由对应服务管理。
