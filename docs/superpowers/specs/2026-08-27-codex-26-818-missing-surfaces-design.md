# Codex 26.818 局部样式兼容设计

## 目标

修复 Internet Angel 主题在新版 Codex 任务页中的两个局部缺口：延迟挂载的环境信息面板没有获得专属样式，以及输入框后方的两层原生渐隐仍显示为黑色底板。

## 范围

- 保留现有 `data-angel-component` 分类和共享运行时架构。
- 用现有动态重新分类逻辑覆盖延迟挂载的环境信息面板，不新增第二套观察器。
- 在共享基础 CSS 中精确清除 Codex 26.818 的两种输入区渐隐层。
- 通过现有同步工具生成 macOS、Windows 和 Linux 平台副本。
- 不合并上游 `v1.5.16` 的其他改动，不修改主题包、安装器、版本号或发布配置。

## 实现

环境面板继续使用现有结构与语义信号识别。回归测试需要证明面板在初始分类后延迟挂载时仍会被标记，且相似弹层不会被误判。

底部渐隐只匹配非首页主区域内 Codex 26.818 的完整工具类签名：高度为主输入区的 `from-surface via-surface` 渐隐和输入区顶部的 `from-surface to-transparent` 渐隐。两者都清除 `background` 和 `background-image`，不扩大到通用渐变元素。

## 验证

- 先增加会失败的共享运行时断言，再添加最小 CSS 改动。
- 运行共享 renderer、Internet Angel、macOS renderer 和运行时同步检查。
- 运行 `git diff --check` 与相关 JavaScript 语法检查。
- 只有可信 CDP 会话可用时才做热注入与截图验证；否则明确保留实机验证缺口。
