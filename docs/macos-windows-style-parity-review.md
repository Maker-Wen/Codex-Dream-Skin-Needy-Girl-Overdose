# Windows 样式同步至 macOS 改动评估

更新时间：2026-08-12

状态：本地实现、适用自动化验证、Windows 便携回归复核、macOS 当前 revision
的 Light / Dark verifier 及 Auto 恢复均已完成；使用本仓库文件的 macOS 工作区截图、
真实 Windows 视觉与 PowerShell 验证仍待完成。尚未提交、推送、创建 PR 或发布。

## 1. 评估结论

本次目标是以当前 Windows Internet Angel 样式和行为作为参考，将对应的
Composer、Projects/PR、右侧工作区、Dialog、菜单、Tooltip、Diff 和源码视图
覆盖同步到 macOS。

经审查修正后，当前实现已经补齐此前发现的确定差异：

- macOS 不再把无 `ComposerLayoutRoot` 的 Composer Footer 误标为 Composer。
- 固定和浮动左栏均未挂载时，右侧 `aside` 内的 Composer 仍能获得公共部件标记。
- macOS 的通用 Composer 首帧表面、内部原生 wrapper 清理和 Diff 色值与
  Windows 参考实现对齐。
- macOS 菜单补齐 Windows 的三色顶条、渐变分隔线和快捷键文字样式。
- Projects / PR sticky header 补齐 Windows 的 `::after` 渐隐层。
- Dark 模式无 `role` 的 Radix / slot Tooltip 补齐 Windows 的首帧表面和 SVG 箭头样式。
- 永久不开放 Shadow Root 的 Diff host 会耗尽有界检查，不再无限轮询。
- 当前 Codex 的 assistant Markdown 通过现有语义属性获得公共组件标记，Light 正文
  不再继承暗色壳白色前景。
- macOS verifier 会分别验证 Light 的 adaptive Environment 表面和 Dark 的渐变表面，
  两者都要求 Angel 三色 accent strip。
- Light `activity-header` 仅重映射实际获胜的 conversation body token，工具状态行恢复
  深色可读文字，固定深色的 detail / output 不受影响。
- Windows 专项复核发现并修复共享 Light 层追加到 Windows base 后的 Settings 菜单、
  Settings 输入框、Settings 搜索框和 side-workspace 选中态级联覆盖；placeholder 与
  选中态后代也有对应回归合同。
- Light assistant 的透明 `blockquote` 与 inline `code` / `kbd` 使用 adaptive 深色文字；
  opaque 代码块、表格和 details 等固定深色表面继续使用浅色文字。
- 结构识别出的 fallback 左栏会参与 Composer 排除，左栏输入不会被误标为 Composer。
- Diff `attachShadow` hook 在 cleanup 后会失活；外部 wrapper 即使保留旧 hook 也不能
  恢复主题样式，后续注入仍可解包失活 hook 并最终恢复原生实现。
- 任务页打开已识别的右侧源码工作区时，任务 header 的状态装饰会被隐藏，避免侵入
  原生标签区域；无工作区或仅有浮动 Environment 面板时保持原样。

共享源、生成资产和完整适用回归均已通过。macOS 代表性任务页的 Light revision
`7ba53c8d7c68e2e32efc` 与 Dark revision `c743552e1c9f0336548b` 均通过 verifier，
且没有文档溢出。当前仍不能把跨平台状态写成“视觉一致性已全部完成验收”，因为本机
不能执行 Windows PowerShell 或真实 Windows 视觉检查，其他路由也未在本轮逐项打开。

## 2. 目标与范围

### 2.1 包含范围

- Windows 与 macOS 的 Internet Angel Dark / Light 颜色映射
- Composer 及其内部原生表面
- 多 Composer 和右侧 Composer 识别
- Projects / PR 主框架、顶部栏和输入区域
- 已识别的右侧文档、终端、协作和 side-chat 工作区
- Dialog、Radix 菜单、Popover 和 Tooltip
- 文件 Diff、源码视图和 `diffs-container` Shadow DOM
- 主题切换、节点卸载和延迟挂载时的样式清理

### 2.2 不属于本次验收范围

- Linux Renderer 或 Linux 实机视觉一致性
- Windows Acrylic、Win32、托盘、安装器和窗口外观
- 拖动分隔栏时右侧工作区颜色变化
- 强制使用 Dark 模式
- 主题或预设迁移
- 版本号、PR、Release 和发布流程

Linux 的 extension CSS / JS 仍会被现有同步工具机械更新，因为三个平台继续消费
同一套 extension 源文件；这不代表 Linux 是本次功能验收目标。

## 3. 实现边界

### 3.1 Windows 基准

以下 Windows 专属基准文件没有修改：

- `windows/assets/dream-skin.css`
- `windows/assets/renderer-inject.js`

Windows 仍保留独立 base CSS、Renderer、Acrylic 和 Win32 处理。共享 extension
会继续追加到 Windows payload，因此生成的 Windows extension 副本会随共享源变化；
聚焦测试使用 Windows 现有 Composer 识别条件和 Diff 色值公式作为对照。

### 3.2 macOS 对齐路径

macOS 通过现有 `runtime/` 源文件接收对齐逻辑：

- `runtime/dream-skin.css`：Composer 首帧表面、内部 wrapper 清理和 portal Tooltip base
- `runtime/renderer-inject.js`：公共部件识别和多 Composer fallback
- `runtime/internet-angel-extension.css`：组件表面、Dark / Light 和 Diff host 样式
- `runtime/internet-angel-extension.js`：组件分类、Diff Shadow 样式和生命周期

生成资产由 `tools/sync-runtime-assets.mjs` 维护，不直接手工修改平台副本。

## 4. 关键修正

### 4.1 Composer 识别

macOS Renderer 现在会：

- 收集多个带可编辑输入的 Composer owner
- 优先选择最近的 `ComposerLayoutRoot`
- 排除标准 Composer 已拥有的输入
- 排除固定或浮动左栏、Dialog 和 Modal 输入
- 排除 Footer、Toolbar 和 Editor owner
- 保留固定或浮动左栏未挂载时的右侧 Composer

稳定左栏 selector 缺失时，Renderer 会在主内容附近识别结构 fallback
`nav[aria-label]`。该节点既获得公共 sidebar 标记，也参与 Composer 排除，避免其内部
输入被误标；没有可识别左栏时，右侧 `aside` 内的 Composer 仍会保留。

### 4.2 Composer 首帧样式

macOS base CSS 新增与 Windows 通用 Composer 语义一致的规则：

- `data-ds-part="composer"` 表面
- 右侧 `ComposerLayoutRoot` 在公共标记发布前的首帧表面
- 文字、背景、边框、阴影和模糊处理
- Footer、RichTextInput、Body、Attachments 和 `rounded-2xl` 内层清理

`rounded-2xl` 清理只存在于已识别的 Composer 根内部，不是全局规则。

### 4.3 Dark 与 Light

共享 extension 使用 `--angel-adaptive-*` 作为跨平台入口。Windows 优先读取
`--dream-*`，macOS 缺失时回退到 `--ds-*`。

普通 Light 表面使用 adaptive 文字和背景。Assistant 的透明 `blockquote` 与 inline
`code` / `kbd` 使用 adaptive 深色前景；Composer、Settings、Terminal、opaque 代码块、
表格和 details 等固定深色表面继续使用浅色前景。Diff Shadow 使用 adaptive
表面和文字 token。Radix 菜单的空闲项使用 adaptive 文字，Hover、Focus 和选中状态
保留高对比浅色文字。

实机检查还暴露了新版 Codex 的两处 Light 级联变化。Assistant content-search key 已不再
稳定以 `:assistant` 结尾，因此共享 classifier 复用
`data-markdown-text-style="assistant-message"` 标记当前语义节点，并把它加入有界
mutation hint。Activity 子节点的原生 `!important` utility 则实际读取
`--color-token-conversation-body`；共享 Light 规则只在已分类的 `activity-header` 上把
该 token 映射为 `--angel-adaptive-text`，不扩到固定深色 activity detail / output。

上述 activity 规则位于 Windows 与 macOS 共用的 extension 路径。改动前的 Windows
System Light 副本同样缺少该 token 保护，生成后的副本已获得修复，因此不能把原
Windows Light 实现视为对当前 Codex DOM / token 已有完整兼容保障。但两端 Codex
bundle 可能存在版本差异；没有 Windows 实机 computed style 或截图证据时，不能声称
该可见缺陷已在 Windows 上复现。

后续 Windows 专项复核又确认，共享 Light 层追加到 Windows base 后存在三类确定的
级联回归：adaptive Radix 表面会刷浅固定深色的 `settings-menu`，全局 Light input
会覆盖 `settings-input`，固定深色 descendant fallback 会把 side-workspace 选中态的
cyan 覆盖成 paper white。进一步检查还确认 placeholder 伪元素与选中节点内部的
`span` / `div` 不会仅靠父元素继承自动恢复。

当前修复只收紧现有 CSS 作用域：通用 Light input、placeholder 和 Radix 表面排除已
分类的 Settings 固定深色组件；Settings input 与搜索框 placeholder 显式使用浅色
muted，搜索框内部 input 保持透明；选中 side-workspace 节点及与 fallback 相同的
有界文字后代在 fallback 之后恢复 cyan。因此，原 Windows Light 不能被视为已对这批
共享规则完全兼容；当前本地实现已关闭这些可由级联和合同确认的问题，但真实 Windows
视觉结论仍需 Windows 实机证据。

Light Environment 原本就设计为 1 px 边框的 opaque adaptive 表面，而 Dark 使用 2 px
边框和全表面渐变。macOS verifier 现在按 shell appearance 验证各自合同，并共同检查
`::before` 三色 accent strip，避免把正确的 Light 表面误判为主题未命中。

菜单容器同时复用 Windows 的三色 accent strip、cyan/pink 分隔线和 muted monospace
快捷键样式。Projects / PR sticky header 的 `::after` fade 也由共享 extension 提供，
避免 macOS 留下原生渐隐色。

任务页 header 还有一处独立的状态装饰 `::after`。当原生右侧源码工作区缩窄内容区域时，
该装饰原先仍按全窗口的 `right: 84px` 和 `max-width: 28%` 布局，会进入原生标签区。
当前 base CSS 复用现有 `side-workspace` 分类标记，仅在已识别工作区挂载时将该装饰设为
`content: none`；没有增加新的 DOM 分类器，也不影响无工作区或浮动 Environment 面板。

Windows base CSS 会同时覆盖 `[role="tooltip"]`、`[data-radix-tooltip-content]` 和
`[data-slot="tooltip-content"]`。macOS base CSS 现在同步同一套首帧尺寸、边框、渐变、
字体和 SVG 箭头合同，并把 Windows 的 `--dream-*` 变量映射到对应 `--ds-*` 变量。
共享 extension 原有的 `[role="tooltip"]` 覆盖保持不变，因此不会改变 Windows 当前
级联结果；Dark 模式中缺失 `role` 的 Radix / slot portal 也不再退回原生表面。

### 4.4 Diff Shadow DOM

普通页面 CSS 无法穿透 `diffs-container` 的 Shadow Root。共享 extension 会安装
唯一、可清理的 Shadow stylesheet，并与 Windows 使用相同的表面公式：

- 普通表面：`94% surface + 5% accent`
- 抬升表面：`94% raised surface + 6% accent`

延迟生命周期同时覆盖：

- Shadow Root 已存在时立即安装
- 自定义元素延迟定义时通过 `customElements.whenDefined()` 调用当前注册实例
- 已定义元素稍后创建 Root 时每个 host 最多执行 12 次 root-only 检查
- 永久缺少开放 Shadow Root 时检查预算会耗尽并停止 timer
- root-only 检查不重新运行全页组件分类
- 主题切换或 cleanup 时取消 timer、丢弃检查预算并删除所有 owned style

`attachShadow` hook 同时保存 `active` 和原生 `original` 元数据。Cleanup 会先将旧 hook
置为失活，即使后装的外部 wrapper 仍持有该函数，也无法重新安装 Diff 主题样式；下次
注入会解包失活 hook，正常安装本轮 hook，并在最终 cleanup 后恢复原生实现。

## 5. 文件范围

当前有 18 个 tracked 修改文件，另有本评估文档 1 个 untracked 文件。

| 类型 | 文件数 | 说明 |
| --- | ---: | --- |
| `runtime/` 可维护源 | 4 | base CSS、extension CSS / JS、Renderer |
| 平台生成副本 | 8 | macOS 4、Windows 2、Linux 2 |
| 自动化测试 | 4 | 共享 extension / Renderer、macOS 集成和 verifier |
| macOS 验证逻辑 | 1 | `macos/scripts/injector.mjs` |
| 连续性记录 | 1 | `TASK_PROGRESS.md` |
| 未跟踪评估文档 | 1 | 本文件 |

Windows 和 Linux 的 extension 文件属于共享源生成副本，不包含独立手写逻辑。

## 6. 自动化证据

本轮新增或加强的断言包括：

- Footer 内存在输入但没有 `ComposerLayoutRoot` 时不得标记 Composer
- 左侧栏未挂载时右侧 Composer 仍必须标记
- 结构 fallback 左栏内的 `ComposerLayoutRoot` 不得标记 Composer
- macOS 包含 Windows 对应的 Composer 首帧与 wrapper 清理规则
- Diff Root 延迟挂载后能够安装样式
- 等待 Diff Root 不增加完整 `classify()` 次数
- cleanup 后异步回调不得重新安装样式
- 永久缺少 Shadow Root 时有界检查必须耗尽
- macOS 与 Windows Diff 使用相同的 `94/5` 和 `94/6` 色值公式
- 菜单 accent strip、separator、shortcut 和 Projects / PR fade 与 Windows 对齐
- Dark 模式无 `role` 的 Radix / slot Tooltip 包含 Windows 对应的首帧表面和 SVG 箭头规则
- extension 属性观察仍只允许 `data-ds-part`
- 当前 assistant 语义节点在初始分类和晚挂载后都必须获得公共标记
- Light `activity-header` 只重映射实际获胜的 conversation body token，不触及固定深色
  activity detail / output
- Light Environment 接受 1 px opaque adaptive 表面并要求 accent strip；Dark 仍要求
  2 px 渐变表面
- 通用 Light input 与 placeholder 不得覆盖固定深色 `settings-input`
- 固定深色 Settings placeholder 必须保留可读的浅色 muted 前景
- 通用 Light input 与 placeholder 不得覆盖 wrapper 标记的 `settings-search`，其内部
  input 必须保持透明且使用浅色前景
- adaptive Light Radix 容器不得覆盖固定深色 `settings-menu`
- side-workspace 选中节点及其有界文字后代必须在 fixed-dark fallback 后恢复 cyan
- Light assistant 的透明 `blockquote` 不得被固定深色前景覆盖
- Light inline `code` / `kbd` 必须恢复 adaptive 文字，opaque 代码表面仍保留浅色文字
- 外部 wrapper 持有 cleanup 前的 `attachShadow` hook 时不得恢复 Diff 样式，后续注入
  必须能解包该失活 hook
- 已识别的 side-workspace 挂载时必须隐藏任务 header 状态装饰，避免覆盖原生标签

已通过的聚焦检查：

- `node tools/internet-angel-extension.test.mjs`
- `node tools/renderer-runtime.test.mjs`
- `node macos/tests/internet-angel-macos.test.mjs`
- `node macos/tests/renderer-inject.test.mjs`
- `node macos/tests/renderer-verification.test.mjs`
- `node windows/tests/renderer-inject.test.mjs`
- `node tools/sync-runtime-assets.mjs --check`
- 相关 JavaScript 语法检查
- `git diff --check`

Windows 专项复核还通过：

- Windows 全部 17 个 JavaScript / module 文件语法检查
- 9 个可在 macOS 执行的 Windows Node 回归：Renderer、响应式 CSS、Bootstrap、
  Session、one-shot、窗口 readiness、图像元数据、路径 containment 和 schema contract
- Windows payload template 合同 `6/6`
- Windows injector self-test
- System、Acrylic 和显式预设目录 payload 构造
- 非法 `blur` window material 拒绝

one-shot 首次执行因沙箱禁止监听 `127.0.0.1` 返回 `EPERM`；同一未修改命令获得本机
回环权限后通过。这是测试环境限制，不是代码断言失败。

最终代码上的完整验证还通过：

- 完整 macOS 回归套件，Doctor 按显式环境变量跳过
- macOS Swift build
- macOS XCTest `10/10`
- macOS、Windows 和 Linux payload 完整性检查
- 两个 macOS Internet Angel 预设 payload 检查
- macOS 与 Windows payload template 合同测试
- Safe CSS、ZIP / import、事务、签名运行时、配置和状态回归

完整套件中的 Doctor 按显式环境变量跳过；之后通过受校验的本机 CDP endpoint 对当前
revision 分别执行了 Light / Dark verifier。此前截图因跨项目取证错误已撤下。

## 7. 实机证据与剩余门禁

### 7.1 macOS 当前 revision

本轮通过项目既有的 loopback CDP 注入器完成 payload 级验证：

- Light revision `7ba53c8d7c68e2e32efc`：exact verifier `pass=true`；可见 assistant
  正文和 inline code 计算色均为 `rgb(32, 30, 36)`，文档横向和纵向 overflow 均为
  `false`。
- Dark revision `c743552e1c9f0336548b`：exact verifier `pass=true`；可见 assistant
  正文和 inline code 保持浅色前景，文档横向和纵向 overflow 均为 `false`。

更正：此前 Light / Dark / Auto 工作区截图打开的是另一个 AnimalGit 项目的
`Day6.lua`。该文件没有被修改，但跨项目截图不能作为本仓库验收证据，现已全部从本评估
结论中撤下。任务 header `::after` 防重叠规则已有自动化合同覆盖；使用本仓库文件完成
Light / Dark / Auto 工作区实机截图仍是待执行门禁。

实机过程中先后发现并修复 assistant 语义标记、Light Environment verifier 过时、
Light activity token，以及透明 `blockquote` / inline code 前景四类问题。当前实机
证据覆盖代表性任务页和可见 Environment；Diff Shadow、右侧源码工作区、右侧第二
Composer、Projects / PR、Dialog、菜单和 Tooltip 等路径仍以自动化合同为主，本轮没有
逐页打开并声称全量视觉验收。

测试结束后，持久主题配置已恢复为 `appearance=auto`，当前跟随原生 Dark 设置并以
Auto revision `8d161a701a54d543ef1e` 通过 exact verifier；无 Dialog 的右侧源码工作区截图
不再作为验收证据。持久
`~/Library/Application Support/CodexDreamSkinStudio/theme/theme.json` 和
`~/.codex/config.toml` 的 SHA-256 分别保持
`0ba8d94c7974b01aa3b05886e65afc3323591996f2db7f2d759236019797c430` 与
`b341d7f65ccbb7cc2d52321e6d825ac0e9f5d70370d9feb4559dda0f5ad10dfb`。主题清单仍为
`appearance=auto`；原生 `config.toml` 为 `appearanceTheme="dark"`，Auto 当前跟随
Dark shell。

### 7.2 Windows 验证

当前 Windows diff 只有共享源生成的 `windows/assets/internet-angel-extension.css` 与
`windows/assets/internet-angel-extension.js`。Windows base CSS、Renderer、injector、
PowerShell、Acrylic、Win32 和安装器源均未修改。同步检查确认三端 extension 副本与
共享源一致。

本机已通过 17 个 Windows JavaScript / module 语法检查、9 个便携 Node 回归、Safe
CSS `12/12`、payload template `6/6`、injector self-test，以及 System、Acrylic 和
显式预设 payload 构造。System payload 包含共享 Internet Angel extension / classifier；
Acrylic 按原合同排除该 classifier 并继续加载 Acrylic overlay，未进入本次共享 CSS
路径。非法 `blur` material 仍 fail closed。

当前 macOS 主机没有 Windows PowerShell 或 `pwsh`。因此完整 `run-tests.ps1` 及其
PowerShell 5.1 / 7、Win32 HWND、窗口效果、reparse / ADS、注册表、快捷方式、Setup
和真实 Windows renderer 生命周期仍需 Windows CI 或实机执行。Dark / Light 的
computed style、交互状态和截图对照也未在 Windows 上完成；当前证据只能表述为
“本机可执行的 Windows 门禁通过”，不能表述为“Windows 平台已完整验收”。

## 8. 风险评估

| 风险 | 等级 | 当前处理 | 剩余风险 |
| --- | --- | --- | --- |
| Codex 内部 class 变化 | 中 | 公共部件标记、Windows reject 条件和受限 fallback | 新结构仍需更新 selector contract |
| Light 局部对比遗漏 | 中 | adaptive token、Settings / 选中态级联合同及 macOS Light / Dark 实机检查 | Windows 实机与未来 Codex token / DOM 变化仍需复核 |
| Shadow Root 生命周期变化 | 中 | 当前实例回调、每 host 12 次检查、失活 hook 解包和 cleanup | 上游更换组件实现时需复核 |
| 多 Composer 误识别 | 低 | 要求可编辑输入并排除 Footer、左栏和 Dialog | 未知 owner 结构仍需 fixture |
| 共享资产漂移 | 低 | 生成工具和字节一致性检查 | 手工跳过同步工具时仍可能漂移 |

## 9. Git 与发布状态

- 分支：`codex/macos-windows-style-parity`
- 提交：未创建
- 推送：未执行
- PR：未创建
- 版本：未提升
- Release：未触发
- 当前公开 `v1.5.14`：不包含本次改动
