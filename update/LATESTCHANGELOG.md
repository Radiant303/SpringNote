## ✨ 更新日志

### 界面优化

* 优化便签编辑右上角“已保存”和编辑预测提示的切换显示。([#71](https://github.com/Radiant303/SpringNote/issues/71)；感谢 [Radiant303](https://github.com/Radiant303))
* 优化 Markdown 渲染样式，优化标题、表格、公式、任务列表等内容的显示效果。
* 优化官网样式，完善配置教程。


### 功能新增

* 新增深色模式支持，并适配 Windows/macOS 桌面组件。([#72](https://github.com/Radiant303/SpringNote/pull/72)、[#73](https://github.com/Radiant303/SpringNote/pull/73)；感谢 [jinnian0703](https://github.com/jinnian0703))
* 新增应用和桌面组件壁纸功能，支持默认背景、透明度、模糊和蒙版等配置。([#76](https://github.com/Radiant303/SpringNote/pull/76)；感谢 [lovewanting](https://github.com/lovewanting))
* 新增便签页编辑、分栏和预览模式。
* 新增 Markdown 编辑器语法高亮，支持在设置中开关，默认启用。
* Markdown 渲染中的链接支持点击后使用浏览器打开。
* 快捷键设置支持直接录入组合键，并可重置或清除全局快捷键。
* 新增存储管理功能，可扫描 `notes/images` 中未被便签引用的图片并在确认后清理。

### 问题修复

* 修复便签页自动同步时上传对象漏传的问题。
* 修复回忆书本地降级检索中的工具调用上下文格式不兼容，导致部分模型请求返回 400 的问题。
* 修复 Markdown 渲染中的表格、嵌套方括号和部分链接解析异常。
* 修复桌面组件高频拖动时状态循环、纯色切换异常以及字体缩放下三态控件边界异常的问题。
