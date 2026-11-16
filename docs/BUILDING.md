# 论文伴侣是怎么搭出来的

> 这份文档写给想自己复现一个「AI 桌面应用」的人。它不讲空泛的架构，而是按这个仓库真实的代码，拆成一条可以照着走的路：先跑通一条最细的端到端链路，再一圈圈加能力。

## 0. 先看清成品是什么

论文伴侣本质上做四件事：

1. **读 PDF**：渲染、翻页、缩放、选中文字、框选区域。
2. **和模型对话**：把论文内容 + 用户问题拼成上下文，流式请求，渲染 Markdown / 公式 / 表格。
3. **精翻**：逐页请求翻译，把 Markdown 转成 LaTeX，编译成 PDF，替换原文显示。
4. **工程化**：本地保存、缓存、错误处理、打包、签名、CI、跨平台。

```
用户
 │ 打开 PDF / 选中 / 提问 / 点翻译
 ▼
┌──────────────┐   文本+图片    ┌──────────────┐
│ 阅读器        │ ────────────▶ │ 模型 API      │
│ PDFKit/pdf.js │ ◀──────────── │ OpenAI 兼容   │
└──────┬───────┘   流式 Markdown └──────────────┘
       │
       ├─ 聊天：Markdown → marked → KaTeX → WKWebView / Electron
       └─ 翻译：Markdown → LaTeX → xelatex/Tectonic → PDF → 回填阅读器
```

两套实现（macOS 原生、Windows Electron）共享的不是 UI 代码，而是三样「协议」：**OpenAI 兼容接口、Markdown + LaTeX 约定、提示词与缓存策略**。这是跨平台能省力的关键。

---

## 1. macOS 应用的最小骨架

### 1.1 不用 Xcode 也能做 App

这个项目用 `swiftc` 直接编译，再手工拼出 `.app` 目录（见 `build.sh`）：

```
论文伴侣.app/
└── Contents/
    ├── Info.plist              # 应用元信息（bundle id、版本、图标、文档类型）
    ├── MacOS/PaperCompanion    # 可执行文件
    └── Resources/              # 插画、网页资源、icon.icns
```

`build.sh` 的核心只有四步：

```sh
swiftc -O -target arm64-apple-macos13.0 \
  -framework WebKit -framework AppKit -framework PDFKit ... \
  Sources/*.swift -o build/PaperCompanion

cp Info.plist "$BUNDLE/Contents/Info.plist"
ditto Resources "$BUNDLE/Contents/Resources"
codesign --force --sign - "$BUNDLE"      # ad-hoc 签名
```

**为什么可以不用 Xcode 工程？** 因为 Swift 编译器本身就是完整的；Xcode 只是替你管理 bundle、签名和资源。小项目手写 `build.sh` 反而更透明、更容易进 CI。

**练习 1**：新建一个空目录，只放一个 `main.swift` 打印 "hello"，用同样的 `swiftc` 命令编译，再手工拼一个能双击打开的 `.app`。

### 1.2 启动链路

`Sources/main.swift` 的骨架是所有 AppKit 应用的通用模式：

```swift
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
```

`AppDelegate.applicationDidFinishLaunching` 里做三件事：准备数据目录、建菜单、创建主窗口。

**练习 2**：把业务代码全部删掉，只留下一个 800×600 的窗口，确认能启动、能关闭。

---

## 2. PDF：阅读、选中、坐标

### 2.1 三件套

- `PDFDocument`：整篇文档
- `PDFPage`：单页
- `PDFView`：负责显示、缩放、滚动、选择

打开一个 PDF 只需要：

```swift
let doc = PDFDocument(url: url)
pdfView.document = doc
pdfView.autoScales = true
```

翻页、目录、文字提取都在 `PDFPage` 上：`page.string` 拿文字，`page.numberOfCharacters` 判断是不是扫描版（没有文字层）。

### 2.2 选中与坐标

`PDFView` 自带文字选择，但你要拿到「选了什么、在第几页、在页面上的哪个位置」，需要 `PDFSelection`：

```swift
if let selection = pdfView.currentSelection,
   let page = selection.pages.first {
    let text = selection.string
    let bounds = selection.bounds(for: page)   // PDF 坐标
}
```

框选则是反过来：先把鼠标的视图坐标转成页面坐标，再存成**归一化比例**（0–1），这样换缩放、换窗口大小都不会错位。

**练习 3**：选中一段文字，打印它的页码和文本；再画一个矩形，打印归一化坐标。

---

## 3. 接一个大模型：一次流式请求

### 3.1 协议很简单

所有 OpenAI 兼容服务都是：

```
POST {baseURL}/chat/completions
Authorization: Bearer <key>
{ "model": "...", "messages": [...], "stream": true }
```

返回是 SSE：一行行 `data: {...}`，最后 `data: [DONE]`。解析时不要假设一次网络包就是一行，要维护缓冲区按 `\n\n` 切分。

`Sources/DeepSeek.swift`（macOS）和 `desktop/src/core.cjs` 的 `streamCompletion` 做的都是这件事：拼接 delta → 回调 UI → 处理 `finish_reason` 和异常。

### 3.2 三个必须处理的现实问题

1. **超时与取消**：用户可能中途停止，或者网络卡住。要能 `abort`，并且不要把手动取消当成错误弹窗。
2. **Key 存在哪**：最早用 Keychain，但签名是 ad-hoc 时每次读取可能弹系统授权框，卡住主线程。最后改成 `~/Library/Application Support/PaperCompanion/credentials.json`（权限 0600），启动时后台预热。Windows 用 Electron `safeStorage`（DPAPI）。
3. **上下文不是越多越好**：整篇论文可能几万字，全塞进去既贵又慢。现在的做法是全文截断 + 当前页 + 选中内容 + 最近对话 + 早期摘要。这是一个「够用」的工程折中，也是以后做检索（RAG）的起点。

### 3.3 提示词是产品的一部分

以翻译为例，提示词里写清楚：保留标题/章节/表格/公式编号、数学必须 `$...$`、不要页眉页脚、不确定的公式要标注。聊天提示词则规定：先结论、引用原文标页码、逐符号解释、给类比、控制长度。

**重要认知**：提示词能提高概率，但不能保证。真正可靠的是「工程兜底」——校验、重试、检测异常、失败回滚。比如表格被模型压平成文字时，程序检测到「有表题、有数字、没有管道表」，就再请求一次专门整理表格。

**练习 4**：先写一个命令行脚本，读一个 API Key，发一次流式请求，把 delta 打印到终端。跑通它，你就理解了整个聊天功能的一半。

---

## 4. 让回答好看：WKWebView + marked + KaTeX

`NSTextView` 做 Markdown 很痛苦，公式和表格几乎不可行。项目最终把聊天渲染放进一个本地网页：

- `Resources/Chat/index.html`：marked（Markdown）、KaTeX（公式）、DOMPurify（清洗）、highlight.js（代码）
- `Sources/RichTranscript.swift`：`WKWebView` 加载本地文件，原生侧通过 `evaluateJavaScript` 推数据，通过 `WKScriptMessageHandler` 收「复制/跳页」事件

```swift
web.loadFileURL(root.appendingPathComponent("Chat/index.html"),
                allowingReadAccessTo: root)
web.evaluateJavaScript("window.renderMessages(payload)")
```

**为什么要 DOMPurify**：模型输出是不可信内容，可能带 `<script>`。渲染前必须清洗，且页面 CSP 禁止远程脚本。

**流式渲染的细节**：不是每个 token 都重排整个页面，而是攒 100–150ms 再渲染一次，并保持「用户没往上翻就自动滚到底」。

**练习 5**：做一个 30 行的 HTML 页面，输入一段 Markdown（含 `$...$`），用 marked + KaTeX 渲染出来。这一步跑通，聊天界面就不神秘了。

---

## 5. 译文流水线：LLM → LaTeX → PDF

这是整个项目最重的部分，也是「论文伴侣」和普通 PDF 阅读器的分水岭。

### 5.1 为什么用 LaTeX

因为论文需要：公式、表格、分栏、编号、字体。用 Markdown 直接转 HTML 再打印，公式和表格很难稳定。XeLaTeX 是学术界现成的排版引擎，代价是要装 TeX（macOS 用系统 `xelatex`，Windows 打包 Tectonic）。

### 5.2 流程

```
每一页：
  文本（+ 可选的两张半页图，供视觉模型核对公式）
    → 模型返回 Markdown（$...$ 公式、| 表格）
    → TranslationTeX 转成 .tex
    → xelatex 编译成 PDF
    → 全部页编译完，替换阅读器里的 PDF
```

`Sources/TranslationTeX.swift` 做四件事：

1. **转义**：正文里的 `% & # _` 等字符转义，避免破坏 TeX。
2. **公式校验**：只允许安全的数学命令，拦截 `\input`、`\write18` 这类危险原语。
3. **表格**：Markdown 管道表 → `tabular`/`longtable`；宽表缩放到栏宽。
4. **版式**：`PaperLayout` 读取原 PDF 的纸张、边距、单双栏，译文尽量保持同样的版式。

### 5.3 踩坑清单（这些都是真实发生过的）

- 模型把表格压成一行行文字 → 检测 + 二次「整理表格」请求 + 提示词强制管道表。
- 两栏论文里宽表挤成一列 → 宽表用 `resizebox` 缩放到栏宽。
- `longtable` 不能放进 `multicols` → 两栏时换成 `tabular`。
- 公式白名单太严，`\top` 被拒 → 改成黑名单，只拦危险命令。
- 改提示词后旧缓存还在 → 缓存 key 里带 prompt 和版本号，升级时自动失效。

### 5.4 缓存设计

按「文档 + 语言 + 提示词 + 版本」做 key，按页缓存译文。好处：停止后能继续、改语言不串、升级提示词能强制重翻。代价：缓存会膨胀，需要清理策略。

**练习 6**：拿一页 Markdown（含一个公式和一个表格），写脚本转成 `.tex` 并调用 `xelatex` 编译，打开 PDF 看效果。这是译文功能的原型。

---

## 6. 桌面工程化：线程、状态、打包

### 6.1 主线程只做 UI

编译 LaTeX 可能几十秒，网络请求可能超时。这些都必须离开主线程。项目里用后台队列 + `generation` 令牌：切换文档时令牌加一，旧任务的回调直接丢弃，避免「翻到新论文，旧译文又贴上来」。

### 6.2 状态与持久化

每篇论文的阅读进度、对话、译文缓存、笔记都存在 `Application Support/PaperCompanion/`。写入用「临时文件 + rename」保证原子性，避免崩溃时写坏 JSON。

### 6.3 打包与分发

```
build.sh → 论文伴侣.app → codesign（ad-hoc）→ hdiutil 打 DMG
```

ad-hoc 签名不需要证书，但别人下载后 Gatekeeper 会拦，需要右键打开或 `xattr -dr com.apple.quarantine`。要彻底消除警告，必须买 Apple Developer 证书（$99/年）或做公证（notarization）。

### 6.4 可观测性

`PAPER_COMPANION_DEBUG=1` 打开日志；关键路径（翻译页数、图片字节、编译耗时、错误原文）都写日志。没有日志的桌面应用，出问题只能猜。

---

## 7. Windows 版：为什么选 Electron

macOS 版验证了产品，但 Swift 不能复用到 Windows。Electron 的吸引力在于：

- PDF.js 直接渲染 PDF 和文本层；
- 聊天界面可以复用 marked + KaTeX（本来就是网页）；
- 一套 JS 代码同时跑 Windows/macOS/Linux。

架构是 Electron 的标准三件套：

```
main.cjs      主进程：窗口、文件、网络、编译、Key 加密
preload.cjs   桥：只暴露白名单 IPC
renderer.js   界面：PDF.js、聊天、翻译流程
```

安全要点：`contextIsolation: true`、`sandbox: true`、CSP、自定义 `companion://` 协议只读资源、IPC 校验 sender。

Windows 的 TeX 用打包进去的 Tectonic（首次编译联网下载宏包），安装包用 electron-builder 生成 NSIS + ZIP，CI 在 `windows-2022` 上跑 Playwright 真界面测试、编译、打包和产物校验。

**练习 7**：用 Electron 写一个最小应用：打开 PDF、显示页数、一个输入框把文字发到本地 mock 服务。这就是 Windows 版的雏形。

---

## 8. 建议的学习路线（8 个里程碑）

| 里程碑 | 做什么 | 验收标准 | 参考文件 |
| --- | --- | --- | --- |
| M1 | 窗口 + 打开 PDF | 能选择文件并显示第一页 | `main.swift`、`ReaderPane.swift` |
| M2 | 翻页、缩放、选中 | 选中文字能拿到页码和文本 | `ReaderPane.swift` |
| M3 | 命令行流式请求 | 终端能逐字打印模型回答 | `DeepSeek.swift` / `core.cjs` |
| M4 | 网页渲染 Markdown | 公式、表格、代码块正常显示 | `Resources/Chat/*` |
| M5 | 单页翻译 → PDF | 一页 Markdown 能编译成 PDF 并显示 | `TranslationTeX.swift`、`LearningReport.swift` |
| M6 | 多页 + 缓存 + 进度 | 停止后可继续，切页不串 | `TranslationService.swift` |
| M7 | 打包与签名 | 生成可双击的 `.app` / DMG | `build.sh`、`package.sh` |
| M8 | 移植或加功能 | Windows 最小版，或加一个真实功能 | `desktop/*` |

每个里程碑都应该是**端到端可运行**的，不要先写一堆「以后会用」的抽象。

---

## 9. 给你练手的 5 个改动

1. **复制公式 LaTeX**：在聊天消息的公式上右键，复制 `$...$` 源码。（练 DOM 事件 + 剪贴板）
2. **导出笔记 Markdown**：把划线笔记导出成 `.md`。（练数据模型 + 文件写入）
3. **按章节检索**：解析 PDF 目录，把「第 3 节」的文本作为上下文。（为 agent 铺路）
4. **术语表**：翻译前先让模型抽术语，后续页面复用，保证全文术语一致。（练多阶段流水线）
5. **最小评测集**：准备 10 个问题，检查回答是否都带正确页码引用。（练评测思维）

---

## 10. 关键文件索引

| 文件 | 作用 |
| --- | --- |
| `Sources/main.swift` | 启动、菜单、调试参数 |
| `Sources/MainWindow.swift` | 主窗口、工具栏、侧栏、文档生命周期 |
| `Sources/ReaderPane.swift` | PDF 阅读区、选中、框选、译文切换 |
| `Sources/AssistantPane.swift` | 聊天侧栏、笔记、报告入口 |
| `Sources/ChatEngine.swift` | 提示词、上下文、流式对话、记忆摘要 |
| `Sources/DeepSeek.swift` | OpenAI 兼容客户端、SSE 解析 |
| `Sources/TranslationService.swift` | 逐页翻译、并发、缓存 |
| `Sources/TranslationTeX.swift` | Markdown → LaTeX、公式校验、表格 |
| `Sources/PaperLayout.swift` | 读取原 PDF 的版式 |
| `Sources/LearningReport.swift` | 调用 xelatex、超时、导出 |
| `Sources/RichTranscript.swift` | WKWebView 聊天渲染与桥 |
| `Resources/Chat/*` | marked / KaTeX / DOMPurify / 聊天页面 |
| `desktop/src/main.cjs` | Electron 主进程、IPC、Tectonic、Key 加密 |
| `desktop/src/renderer.js` | Windows 界面与全部交互 |
| `.github/workflows/*` | macOS / Windows CI 与发布 |

---

## 11. 最后几条心法

1. **先做细线，再做面积**：先让「打开 PDF → 问一句 → 看到回答」跑通，再谈翻译、笔记、跨平台。
2. **把模型输出当不可信输入**：转义、清洗、校验、超时、回滚，一个都不能少。
3. **可观测性优先**：日志、状态栏、错误原文，比「优雅的抽象」更能救你。
4. **缓存要版本化**：提示词、排版逻辑、模型变了，旧缓存必须能失效。
5. **评测比调参重要**：准备一小套真实问题，每次改动跑一遍，比凭感觉改 prompt 靠谱。

如果只能记住一句话：**这个 App 的难度不在「调模型」，而在「把模型的不可靠输出，变成用户可用的稳定界面」。**
