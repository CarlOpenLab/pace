# 接系统字号：十个角色，不是 129 个数字

Carl 定了全接、分页推进；Ato 加一条：**先只套在「记一笔」一页上**，映射对不对拿这一页试出来，再往别处推。理由我认——映射是猜的，先把 129 处全换掉再发现猜错，回滚就是全仓库回滚。

所以这份给的是**角色表**：先用角色说话，角色后面挂哪个系统样式，是这一轮要验的东西。

---

## 1. 十个角色

一个角色 = 一件在界面上干同样活的字。判断方法：两处字如果换一换，用户会觉得没区别，它们就是同一个角色。

| # | 角色 | 现在用在哪 | 默认字号 | 字重 | 换成 | 行距 | 最多几行 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `display` | 首页金额、统计页大数字 | 38 / 48 | heavy rounded | `@ScaledMetric(relativeTo: .largeTitle)` | — | 1（放不下换行，不缩） |
| 2 | `screenTitle` | 页面大标题 | 34 / 28 | bold | `.largeTitle` / `.title` | — | 1（可截，无障碍读全） |
| 3 | `sectionTitle` | 区块标题、卡片标题、「记一笔」标题 | 16 / 15 semibold | semibold | `.callout`（16）/ `.subheadline`（15） | 2 | 2 |
| 4 | `body` | 正文、说明的主体 | 15 | regular | `.subheadline` | 3 | 不限 |
| 5 | `rowTitle` | 账单行标题、草稿卡标题 | 15 / 16 | medium / semibold | `.subheadline` / `.callout` | 0 | 1（可截，无障碍读全） |
| 6 | `secondary` | 提示、脚注式的说明、隐私说明 | 13 | regular | `.footnote` | 3 | 不限 |
| 7 | `caption` | 日期、计数、单位 | 12 | regular / monospacedDigit | `.caption` | 0 | 1 |
| 8 | `label` | 类型／分类／例句胶囊、切换器两段 | 14 | medium | `@ScaledMetric(relativeTo: .subheadline)` 基准 14 | 0 | 1（放不下换行，不缩） |
| 9 | `micro` | 极小辅助字（角标、状态点旁的数） | 10 / 11 | semibold | `.caption2`（11 的直接对；10 的用 `@ScaledMetric(relativeTo: .caption2)` 基准 10） | 0 | 1 |
| 10 | `button` | 主按钮、次级按钮的字 | 16 | semibold | `.callout` | 0 | 1（换布局，不缩） |

两个角色现在长得像但必须分开：`rowTitle` 和 `button` 都是 15/16、都是重字，区别是行标题可截、按钮不可截——按钮截了就变成「…」，今天已经出过一次。

---

## 1.1 默认字号下必须零变化

接系统字号不是顺手调排版。凡是原字号和系统档位**不相等**的角色，一律用「以原字号为基准的缩放」，不要就近取整：

| 角色 | 原字号 | 系统档位 | 做法 |
| --- | --- | --- | --- |
| `label` | 14 | subheadline 15 | `@ScaledMetric(relativeTo: .subheadline)` 基准 14 |
| `micro` | 10 | caption2 11 | `@ScaledMetric(relativeTo: .caption2)` 基准 10 |
| `display` | 26 / 38 / 48 | largeTitle 34 | `@ScaledMetric(relativeTo: .largeTitle)` 基准原值 |

**相等的那几档直接对，不相等的一律保基准。** 13→footnote、15→subheadline、12→caption、11→caption2、16→callout、17→body、28→title、34→largeTitle，这些数字刚好相等，换成系统样式像素级不变。

我第一版表里把 14 对成 15、10 对成 11，还在旁边写「长 1 点，可接受」——那句是错的：接字号的这一轮里没有「可接受的长大」，只有「不变」和「另立一次改动」。这两种以后再也没法分开。

**验收方式**：同一页在默认字号下，改动前后各截一张，做像素比对，允许的差异只有字体渲染的抗锯齿（每通道 ≤2）。差得更多就是默认样子变了。

---

## 2. 间距也要跟着长，但要封顶

字号放大之后，间距不动会让文字贴在边框上；间距无限放大又会把内容挤出屏幕。规则：

- 卡片内距、块间距、行间距用 `@ScaledMetric(relativeTo: .body)`，**上限 1.6 倍**。
- 现在的基础值：`screen 20`、`cardPadding 20`、`heroPadding 22`、`cardGap 16`、`inner 12`。
- 到 1.6 倍封顶：20 → 32、22 → 35、16 → 26、12 → 19。再大就不长了，交给滚动。
- 行距（行与行之间）跟着字走：正文行距 3 → 用 `.lineSpacing(scaled(3))`，同样封顶。
- 1 点以下的描边、0.5 的分隔线**不缩放**，它们是线不是字。

---

## 3. 这一轮只改「记一笔」一页

拿它试映射，是因为这一页角色最全：`sectionTitle`（切换器下的卡片）、`body`（失败卡正文）、`label`（切换器和胶囊）、`button`（失败卡两颗按钮、保存）、`rowTitle`（金额）、`caption`（日期）。十个角色里占了六个，一页就能看出映射对不对。

这一页要看的三件事：

1. 切换器两段：字放大后还完整吗？段高够吗？（现在段高写死 28，要改成跟着 `label` 缩放）
2. 输入卡：卡高 64 现在写死，要改成「字高 + 上下内距」。
3. 失败卡：两颗按钮在大字号下真的从并排变上下两行；卡片长高之后不会被屏幕切掉底部。

三件都过了，再按 今天 → 草稿确认 → 账单 → 统计 → 设置 的顺序推。

---

## 4. 每一页都要量的六条

在「辅助功能·大」和最大档各截一张：

1. 页面主体没有横向裁切（内容不贴边被切）。
2. 无障碍树里每个文本元素的 label 是完整句子，不是「…」。
3. 并排的两颗按钮在该字号下变成上下两行（量 y 起点不同、宽度等于卡片内距宽）。
4. 卡片之间的间距 ≥16，没被压成 0（「卡片长高了、间距没长」的典型症状）。
5. 可点元素命中高度 ≥44，读无障碍树里的 frame。
6. **键盘顶上来之后，底部那颗按钮还按得到**：大字号 + 键盘是最容易把人卡住的组合，输入框和提交按钮必须在同一个可见区域里，不能一个被顶到屏幕外。

---

## 5. 提前说清：这一轮会暴露的老问题

- **切换器**：两段各占一半，字号一大人会挤。现在的 `minimumScaleFactor(0.85)` 要删——不许把用户选的字压回去；改成段高跟着 `label` 长。
- **例句胶囊**：三颗现在刚好一行，大字号下会换行（见下条通则），不再是横向滚动——我先前写「横向滚动是设计行为」是错的。
- **首页日期行**：已定 `ViewThatFits`（并排 → 两行），这次一起验。
- **工具栏**：系统处理，别自己加尺寸，也别把 `.fixedSize()` 加回来。
- **统计页 48 的大数字**：最大档下允许换行成两行，数字整体不断字，不缩。
- **字号表本身**：CI 只禁**数字字面量**，不禁 `@ScaledMetric` 变量。检查写法是 grep `\.font\(\.system\(size: [0-9]`，目标是 0 处；`.system(size: displaySize, …)` 这种白名单写法不算违规——上一版我把规则写成「`.system(size:` 全部清零」，那会把唯一正确的写法也判违规。

---

## 5.1 胶囊排不下了怎么办：换行，不是滚动

判断标准是**这一排的颗数会不会变多**，不是这一排长不长。

- 颗数固定且少（类型 4 颗、分类 handful、例句 3 颗）：`ViewThatFits`，放得下一行就一行，放不下就换行；行内 8、行间 8；**去掉横向滚动**——留着就是既能换行又能拖，两套手势打架。
- 颗数可能多到没边的地方（将来的筛选、搜索历史）：横向滚动。
- 换行后每一颗都必须完整。半颗胶囊（「退款」只剩「退」）不是滚动提示，是把词切坏了，读出来是个坏掉的词。
- 某颗自己比一整行还宽：改字（找 Camo），不缩字、不加省略号。
- 默认字号下这些改动必须一个像素都不动——这是接系统字号的底线。

---

## 附：角色实现的写法

白名单：只有 `display`、`screenTitle` 这两个角色允许用 `.font(.system(size: <ScaledMetric 变量>, …))`，其余一律走系统样式常量。


```swift
enum PaceFont {
    static let sectionTitle = Font.callout.weight(.semibold)
    static let body         = Font.subheadline
    static let rowTitle     = Font.subheadline.weight(.medium)
    static let secondary    = Font.footnote
    static let caption      = Font.caption
    static let label        = Font.subheadline.weight(.medium)
    static let micro        = Font.caption2.weight(.semibold)
    static let button       = Font.callout.weight(.semibold)
    // display / screenTitle 的尺寸随字号缩放，在调用处用 @ScaledMetric：
    //   @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 38
    //   .font(.system(size: displaySize, weight: .heavy, design: .rounded))
}
```
