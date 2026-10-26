# 记一笔：一句话 / 手动 —— 文案（Camo）

对应 `docs/DESIGN-add-mode-switch.md`。落点 `iosApp/iosApp/Copy.swift`。

## 1. 切换器
- 左半 `一句话`，右半 `手动`；两个都是 Button，各自 `.isSelected`。
- 两半都带读屏提示 `切换后已经填的内容不会丢`（承诺，按之前就要听到）。
- 不叫「AI」也不叫「智能 / 自动」。

## 2. 「归属」是内部说法
卡里每个字段用自己的标签（`分类`、`日期`、`账户`），不给这张卡加总标题。

## 3. 手动这边的类型胶囊
`支出` / `收入` / `转账` / `退款`，复用库里现有的四个词。整组读屏 label `类型`，每个胶囊 label 是自己的词，选中带 `.isSelected`。`Copy.Add.Section.type` 的值留着当组的读屏名。

## 4. 工具栏
- 左：`关掉`（视觉是那颗安静的叉），两种模式都有。
- 右：一句话模式不出现；手动模式是 `保存`。

## 5. 一句话这边
- 输入卡标签 `说一句话，出几笔草稿`（不动）。
- 输入框读屏名 `一句话记账`；提示走模型 `写一句话，按键盘上的「发送」`，本机规则 `写一句话，按键盘上的「完成」`。
- 解析中 `正在整理…`。
- 键盘键按 `ai.usesRemoteModel` 分 `.send` / `.done`。

## 6. 菜单里那行
`退款或转账，切到手动`。删掉 `Copy.Ai.Input.manual`（`改成手动记账`）。

## 7. 首页
- 空状态合成一句：`点「记一笔」，说一句话就行。`（不留方位词）
- 主按钮读屏：`记一笔，打开记账页`

## 8. 一起删掉的旧键
- `Copy.Ai.Entry` 整组（`placeholder` / `badge` / `title` / `a11y` / `submit`）
- `Copy.Ai.Input.title`
- `Copy.Ai.Input.manual`
- `Copy.Home.emptySubtitleNoKey` / `emptySubtitleWithKey` → 合成 `Copy.Home.emptySubtitle`

只删入口，别顺手删说明行。

## 9. 片段（可直接用）

```swift
enum AddMode {
    static let sentence = "一句话"
    static let manual = "手动"
    static let switchHint = "切换后已经填的内容不会丢"
}
```

```swift
enum Add {
    static let title = "记一笔"
    static let editTitle = "编辑账单"
    static let save = "保存"
    static let closeA11y = "关掉"
    static let typeGroupA11y = "类型"
}
```

```swift
enum Sentence {
    static let fieldA11y = "一句话记账"
    static let fieldHintRemote = "写一句话，按键盘上的「发送」"
    static let fieldHintLocal = "写一句话，按键盘上的「完成」"
    static let parsing = "正在整理…"
}
```

## 10. 不动
版面/并卡/切换器尺寸/保存胶囊样式（Colo 的规格）；手动表单字段名与校验语；失败卡、草稿卡、类型胶囊的字；「编辑账单」不出现切换器。
