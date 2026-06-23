<!-- We've seen that note-taking tools usually just store text.
But SpringNote treats notes as something that grows over time.
Instead of static records, we model a living system:
  .     *   .       .        o        .       *     .   .
    .   .      |     .    .        .     .     *   .     .
       --o--           SpringNote           .      |   .
    *    |      .   capture → organize → reflect → grow
 .    .     .     .        .        .     .   --*--   .
      .        *      .        .     .        |     .  .
(ASCII art depicting scattered thoughts converging into SpringNote) -->

<h1 align="center">
  <img src="./snapshots/logo.png" width="48" alt="SpringNote Logo" style="vertical-align: -6px;">
  SpringNote
</h1>

<div align="center">

<div>
<img src="https://img.shields.io/badge/Platform-Windows-blue?style=flat&color=76bad9">
<img src="https://img.shields.io/badge/Flutter-3.x-blue.svg?logo=flutter">
<img src="https://img.shields.io/badge/Rust-2024-orange.svg?logo=rust">
<img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg">
</div>
</div>

## 为什么选择SpringNote

市面上的便签软件大多只能帮你保存内容，却很难帮你利用这些内容。SpringNote 因此而生。它不仅能够记录，更能够帮助你整理、沉淀和回顾。通过 AI 自动生成日报、周报和月报，并结合回忆书功能，让过去的记录变成随时可检索、可对话的个人知识资产。


## 核心功能

- **首页工作台**：独创等级、收益、活跃热力图、快速输入框和今日摘要卡片。

  ![SpringNote 首页](./snapshots/index.png)

- **AI 智能生成**：在首页快速输入想法，由 AI 自动整理为结构化内容。

- **便签编辑**：支持日报、周报、月报等记录类型，提供 Markdown 编辑、预览、代码块高亮和 AI 补全预测。

  ![SpringNote 便签](./snapshots/note.png)

- **回忆书对话**：以对话方式检索和整理记忆内容，支持思考过程、工具调用展示与 Markdown 渲染。

  ![SpringNote 回忆书](./snapshots/memories.png)

- **自动报告生成**：启动时可按日期补齐缺失的周报/月报，基于已有日报或周报生成总结。

- **统计面板**：查看记录、活跃度、模型调用和时间范围内的数据概览。

  ![SpringNote 统计面板](./snapshots/setting.png)

- **牛马时钟**：支持自定义日薪和工作时长,自动计算时薪并作为组件展示在页面上。
 
  ![SpringNote 组件](./snapshots/components.png)

- **桌面端极致体验**：支持自定义 Windows 标题栏、托盘、开机自启动、全局快捷键、桌面状态组件和系统字体切换。

## 快速开始

### 下载安装

#### 通过 GitHub 下载

请前往 [Release 页](https://github.com/Radiant303/SpringNote/releases/latest) 下载SpringNote

### 供应商配置

以 **DeepSeek** 为例进行配置说明：

#### ① 添加供应商 BaseURL请填写 https://api.deepseek.com/beta

  ![第一步](./snapshots/configone.png)

#### ② 添加模型 deepseek-v4-flash

  ![第二步](./snapshots/configtwo.png)

#### ③ 编辑模型

  ![第三步](./snapshots/configthree.png)

#### ④ 选择默认模型

  ![第四步](./snapshots/configfour.png)

## 🌍 社区

### QQ 群组

- 1 群：463423961

## ❤️ Special Thanks

特别感谢所有 Contributors和社区成员对 SpringNote 的支持 ❤️

<a href="https://github.com/Radiant303/SpringNote/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Radiant303/SpringNote&max=300&columns=15" />
</a>

## ⭐ Star History

> [!TIP]
> 如果本项目对您的生活 / 工作产生了帮助，或者您关注本项目的未来发展，请给项目 Star，这是我们维护这个开源项目的动力 <3

<p align="center">
  <img src="https://count.getloli.com/@SpringNote?name=SpringNote&theme=miku&padding=7&offset=0&align=center&scale=0.3&pixelated=1&darkmode=auto" alt="visitor count" />
</p>

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=Radiant303/SpringNote&type=Date)](https://star-history.com/#Radiant303/SpringNote&Date)
