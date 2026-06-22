<!--请描述此项更改的动机：它解决了什么问题？是否关联某个 issue？-->
<!--Please describe the motivation for this change: What problem does it solve? Does it close an issue?-->

### 概述 / Summary

<!--请用几句话概括本次改动。-->
<!--Summarize the change in a few sentences.-->

### 改动点 / Changes

<!--请列出主要改动、受影响模块或重要文件。-->
<!--List the main changes, affected modules, or important files.-->

- 

### 截图或录屏 / Screenshots or Recordings

<!--如果涉及 UI 改动，请提供截图、GIF 或录屏。-->
<!--For UI changes, please provide screenshots, GIFs, or recordings.-->

### 验证方式 / Verification

<!--请说明你如何验证本次改动。-->
<!--Please describe how you tested this change.-->

- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `cargo test` in `spring_note/rust`
- [ ] `flutter build windows --release`
- [ ] 手动测试 / Manual test：

---

### 检查清单 / Checklist

<!--如果分支被合并，你的代码可能会被 SpringNote 用户使用。提交前请核查以下内容。-->
<!--If merged, your code may be used by SpringNote users. Please double-check the following items before submitting.-->

- [ ] 😊 本 PR 范围清晰，不包含无关改动。/ This PR has a clear scope and does not include unrelated changes.
- [ ] 👀 我已测试受影响功能，或说明了为什么不适用测试。/ I have tested the affected feature or explained why testing is not applicable.
- [ ] 🖼️ 如果修改了 UI，我已附上截图或录屏。/ If this changes UI, I have attached screenshots or recordings.
- [ ] 🤓 如果修改了依赖，我已更新 `pubspec.yaml`、`pubspec.lock`、`Cargo.toml` 或 `Cargo.lock` 等对应文件。/ If this changes dependencies, I have updated the correct files such as `pubspec.yaml`, `pubspec.lock`, `Cargo.toml`, or `Cargo.lock`.
- [ ] 🔐 本 PR 没有暴露 API Key、Token、本地路径或用户隐私数据。/ This PR does not expose API keys, tokens, local paths, or private user data.
- [ ] 😮 本 PR 没有引入恶意代码。/ This PR does not introduce malicious code.

### 破坏性变更 / Breaking changes

- [ ] 这不是破坏性变更。/ This is NOT a breaking change.
- [ ] 这是破坏性变更，我已在下方说明影响。/ This is a breaking change and I have explained the impact below.

<!--如果这是破坏性变更，请在这里说明影响和迁移方式。-->
<!--If this is a breaking change, describe the impact and migration path here.-->
