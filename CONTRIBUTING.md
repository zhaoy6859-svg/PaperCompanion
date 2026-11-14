# 参与贡献

感谢你对论文伴侣的兴趣！这是一个 macOS 原生 App，代码量不大，欢迎提 Issue 或 PR。

## 环境

- macOS 13+
- Swift Command Line Tools（`xcode-select --install`）
- 只编译 App 不需要 TeX；要让「译文 / 学习报告」跑通，需要 MacTeX 或 TeX Live（`xelatex`）

## 构建与运行

```sh
./build.sh
open "build/论文伴侣.app"
```

安装到 `~/Applications`：

```sh
./install.sh
```

打包 DMG / ZIP：

```sh
./package.sh   # 产物在 dist/
```

## 测试

```sh
swiftc Sources/Models.swift Sources/ConversationMemory.swift Sources/ChatEngine.swift tests/ConversationMemoryTests.swift -o /tmp/pc-memory-tests && /tmp/pc-memory-tests
swiftc -framework AppKit -framework PDFKit Sources/Models.swift Sources/ConversationMemory.swift Sources/PaperLayout.swift Sources/TranslationTeX.swift Sources/LearningReport.swift tests/ReadingPDFTests.swift -o /tmp/pc-pdf-tests && /tmp/pc-pdf-tests
```

`tests/ReaderSwitchTests.swift` 需要图形会话；`tests/RichTranscriptTests.swift` 需要 WebKit。

不要在测试里调用真实模型：设置 `PAPER_COMPANION_HOME` 到临时目录并显式设置 `DEEPSEEK_API_KEY=''`。

## 提交 PR

1. 从 `main` 切分支，改动尽量聚焦
2. 跑一遍 `./build.sh`，确认没有编译警告新增
3. 界面改动附截图；翻译/排版改动附上前后对比
4. 不要提交 API Key、`credentials.json`、`dist/`、`build/`

## 代码风格

- Swift：4 空格缩进，遵循现有文件的命名和分层
- 中文文案放在 UI 层，模型提示词在 `TranslationService` / `ChatEngine`
- 新增用户可见行为时，同步更新 README

## 联系

有任何问题欢迎邮件交流：**zhaoy6859@gmail.com**
