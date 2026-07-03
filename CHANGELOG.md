# 更新日志

## v1.0.2 (2026-07-03)：新增WebDav同步功能

### 界面优化

* 优化快捷键设置页面结构，移除重复标题([#54](https://github.com/Radiant303/SpringNote/pull/54); 感谢[jinnian0703](https://github.com/jinnian0703)))
* 优化设置页面样式，增加了对删除提供商的弹窗二次确认。

### 功能新增

* 新增首页图片解析功能，支持 AI 识别图片内容。([#60](https://github.com/Radiant303/SpringNote/pull/60); 感谢 [lxfight](https://github.com/lxfight))
* 新增WebDav同步功能。([#56](https://github.com/Radiant303/SpringNote/pull/56); 感谢[jinnian0703](https://github.com/jinnian0703))
* 新增首页与回忆书快速提交快捷键([#39](https://github.com/Radiant303/SpringNote/pull/39); 感谢[jinnian0703](https://github.com/jinnian0703))
* 支持便签页面插入和预览图片([#41](https://github.com/Radiant303/SpringNote/pull/41); 感谢[jinnian0703](https://github.com/jinnian0703))
* 新增 Windows/macOS 应用内自动更新功能，新增手动更新选项。([#63](https://github.com/Radiant303/SpringNote/pull/63); 感谢 [lxfight](https://github.com/lxfight))
* 为 Windows 桌面小组件增加跨重启位置持久化功能。([#47](https://github.com/Radiant303/SpringNote/issues/47); 感谢 [lxfight](https://github.com/lxfight))
* 新增回忆书页面AI能力配置功能。

### 问题修复

* 修复 Windows 下多次启动未复用已有窗口的问题。([#52](https://github.com/Radiant303/SpringNote/pull/52)；感谢 [jinnian0703](https://github.com/jinnian0703))
* 修复便签页搜索无法匹配完整内容的问题。([#57](https://github.com/Radiant303/SpringNote/issues/57)；感谢 [Radiant303](https://github.com/Radiant303))
* 修复百炼官方 DeepSeek 无法调用工具的问题。([#46](https://github.com/Radiant303/SpringNote/issues/46)；感谢 [Radiant303](https://github.com/Radiant303))
* 修复 AI 调用统计写入可能不完整的问题。([#49](https://github.com/Radiant303/SpringNote/pull/49)；感谢 [lxfight](https://github.com/lxfight))
* 修复启动时配置文件损坏导致应用崩溃的问题。([#51](https://github.com/Radiant303/SpringNote/pull/51)；感谢 [jinnian0703](https://github.com/jinnian0703))
* 修复桌面组件球形模式快速移动时显示异常的问题。([#38](https://github.com/Radiant303/SpringNote/pull/38)；感谢 [lxfight](https://github.com/lxfight))
* 修复跨平台网络权限声明不一致问题。([#62](https://github.com/Radiant303/SpringNote/pull/62)；感谢 [lxfight](https://github.com/lxfight))

## v1.0.1 (2026-06-26)

### 界面优化

* 将设置图标更换为轮廓风格齿轮图标。
* 优化模型选择页面; 支持按提供商分组展示模型。([#17](https://github.com/Radiant303/SpringNote/pull/17); 感谢 [lxfight](https://github.com/lxfight))
* 设置关于页面新增QQ群联系方式。([#20](https://github.com/Radiant303/SpringNote/issues/20); 感谢 [Radiant303](https://github.com/Radiant303))


### 功能新增

* 支持自定义日报整理提示词。([#7](https://github.com/Radiant303/SpringNote/issues/7); 感谢 [Radiant303](https://github.com/Radiant303))
* 支持 OpenAI /responses API。([#15](https://github.com/Radiant303/SpringNote/pull/15); 感谢 [jinnian0703](https://github.com/jinnian0703))
* 支持自定义配置文件存储目录。([#15](https://github.com/Radiant303/SpringNote/pull/15); 感谢 [jinnian0703](https://github.com/jinnian0703))
* 新增默认模型配置功能。([#17](https://github.com/Radiant303/SpringNote/pull/17); 感谢 [lxfight](https://github.com/lxfight))
* 新增附件的文件路径上传功能。([#21](https://github.com/Radiant303/SpringNote/pull/21); 感谢 [lxfight](https://github.com/lxfight))
* 新增组件圆球化样式及记忆组件位置功能。([#27](https://github.com/Radiant303/SpringNote/pull/27); 感谢 [lxfight](https://github.com/lxfight))
* 新增回忆书检索结果最大字符数配置([#29](https://github.com/Radiant303/SpringNote/issues/29); 感谢 [Radiant303](https://github.com/Radiant303))

### 问题修复

* 修复切换日期时日期选择器按钮闪烁的问题。([#6](https://github.com/Radiant303/SpringNote/issues/6); 感谢 [Radiant303](https://github.com/Radiant303))
* 修复日报内容底部显示被截断的问题。([#12](https://github.com/Radiant303/SpringNote/issues/12); 感谢 [Radiant303](https://github.com/Radiant303))
* 修复启用 max 推理强度参数后 GPT 请求异常的问题。([#15](https://github.com/Radiant303/SpringNote/pull/15); 感谢 [jinnian0703](https://github.com/jinnian0703))
* 修复模型选择列表中的冲突问题。([#17](https://github.com/Radiant303/SpringNote/pull/17); 感谢 [lxfight](https://github.com/lxfight))
* 修复打开便签日报页面无法自动生成日报的问题([#28](https://github.com/Radiant303/SpringNote/issues/28); [Radiant303](https://github.com/Radiant303))

### 平台支持

* 新增Mac端支持。([#21](https://github.com/Radiant303/SpringNote/issues/21); 感谢 [lxfight](https://github.com/lxfight))

## v1.0.0 (2026-06-21)

- 实现了更新功能
- 优化了软件默认图标
- 正式版发布
