# 接系统字号：角色表（Colo 第十三版）+ 本轮落地口径

## 总原则（Colo）
归角色只接缩放，不动基准。这一轮修的是「字号不跟系统走」，不是「把所有 15 都变成 16」。
基准是设计决定，缩放是 bug。

## 角色 → 系统样式 / 缩放写法（本仓库已有）
| 角色 | 原字号/字重 | 写法 |
| --- | --- | --- |
| sectionTitle 15 semibold | 15 / semibold | `.font(PaceType.sectionTitle)` |
| sectionTitleLarge 16 semibold | 16 / semibold | `.font(PaceType.sectionTitleLarge)` |
| body 15 regular | 15 / regular | `.font(PaceType.body)` |
| secondary 13 regular | 13 / regular | `.font(PaceType.secondary)` |
| caption 12 regular | 12 | `.font(PaceType.caption)` |
| micro 11 semibold | 11 / semibold | `.font(Font.caption2.weight(.semibold))` |
| micro 11 regular | 11 | `.font(Font.caption2)` |
| micro 10 semibold（基准 10） | 10 / semibold | `.paceFont(10, .semibold, relativeTo: .caption2)` |
| label 14（基准 14，系统档是 15，不许硬对） | 14 / 任意 | `.paceFont(14, .semibold/.medium/.regular, relativeTo: .subheadline)` |
| 13 semibold | 13 / semibold | `.font(Font.footnote.weight(.semibold))` |
| button 16 semibold | 16 / semibold | `.font(PaceType.button)` |
| display（大数字，封顶 1.5，不低于基准） | 26/34/38/48 | `@ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = <基准>`，再用 `.font(.system(size: min(size, <基准>*1.5), weight: ..., design: ...))` |
| screenTitle 页面标题 | 26 bold 等 | `.paceFont(26, .bold, relativeTo: .title)` |

## 硬规则
- 不许出现 `.font(.system(size: <数字字面量>`（CI 会抓，目标 0 处）。变量写法 `.system(size: heroPointSize, …)` 允许。
- `minimumScaleFactor` 必须为 0 处（今晚删了五次还在代码里活着）。
- 不放省略号、不缩字；放不下就换布局。
- 行高/按钮高写死的 `.frame(height: N)` 若装的是一行字，改成 `.frame(minHeight: N)`，让它跟着字长。
- 默认字号下不许改变视觉：15→subheadline、13→footnote、12→caption、11→caption2、16→callout 都是同点值，像素不变；14 和 10 用基准缩放保原值。
