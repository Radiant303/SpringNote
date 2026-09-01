// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get actionCancel => '取消';

  @override
  String get actionSave => '保存';

  @override
  String get actionClose => '关闭';

  @override
  String get actionConfirm => '确认';

  @override
  String get actionDelete => '删除';

  @override
  String get actionRestore => '恢复默认';

  @override
  String get settingsLanguage => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageZh => '中文';

  @override
  String get languageEn => 'English';

  @override
  String get coreStartupFailedTitle => 'SpringNote 启动失败';

  @override
  String get coreAutoSyncIssueMessage => '自动同步遇到问题，请手动同步';

  @override
  String get coreSidebarHomeLabel => '首页';

  @override
  String get coreSidebarNotesLabel => '便签';

  @override
  String get coreSidebarMemoryLabel => '回忆书';

  @override
  String get coreSidebarSettingsLabel => '设置';

  @override
  String get coreCodeCopy => '复制';

  @override
  String get coreCodeCopied => '已复制';

  @override
  String get coreTreeGenerating => '生成中…';

  @override
  String coreTreeInlineLimitHint(Object hidden, Object limit) {
    return '内联视图最多显示 $limit 个节点，其余 $hidden 个请通过全屏查看';
  }

  @override
  String get coreTreeExitFullscreen => '退出全屏';

  @override
  String get coreTreeFullscreen => '全屏查看';

  @override
  String get coreTreeZoomIn => '放大';

  @override
  String get coreTreeZoomOut => '缩小';

  @override
  String get coreTreeFitAll => '适应全图';

  @override
  String get coreUpdateDialogTitle => '发现新版本';

  @override
  String get coreUpdateCurrentVersionLabel => '当前版本';

  @override
  String get coreUpdateLatestVersionLabel => '最新版本';

  @override
  String get coreUpdateChangeTimeLabel => '更新时间';

  @override
  String get coreUpdateChangeTimeNotProvided => '未提供';

  @override
  String get coreUpdateChangelogTitle => '更新内容';

  @override
  String get coreUpdateChangelogEmpty => '暂无更新内容。';

  @override
  String get coreUpdateChangelogLoadFailed => '更新内容加载失败。';

  @override
  String get coreUpdatePreparing => '正在准备更新...';

  @override
  String coreUpdateDownloading(Object received) {
    return '正在下载安装包 $received';
  }

  @override
  String coreUpdateDownloadingProgress(Object received, Object total) {
    return '正在下载安装包 $received / $total';
  }

  @override
  String get coreUpdateVerifying => '正在校验安装包...';

  @override
  String get coreUpdateExtracting => '正在解压更新...';

  @override
  String coreUpdateExtractingProgress(Object percent) {
    return '正在解压更新 $percent%';
  }

  @override
  String get coreUpdateInstalling => '正在安装更新...';

  @override
  String get coreUpdateLaunchingWindows => '正在启动安装器，SpringNote 即将退出并重启...';

  @override
  String get coreUpdateLaunching => '正在重启并替换为新版本...';

  @override
  String get coreUpdateButtonPreparing => '正在准备更新';

  @override
  String get coreUpdateButtonInstallNow => '立即更新';

  @override
  String get coreUpdateLaunchFailed => '更新启动失败，请稍后重试。';

  @override
  String get coreUpdateErrorUnsupportedPlatform => '当前平台暂不支持自动更新。';

  @override
  String get coreUpdateErrorUpdaterMissing => '更新助手缺失，请下载最新安装包手动更新。';

  @override
  String coreUpdateErrorDownloadFailed(Object status) {
    return '下载安装包失败 ($status)';
  }

  @override
  String get coreUpdateErrorDownloadTimeout => '下载更新超时，请稍后重试。';

  @override
  String get coreUpdateErrorNetworkUnavailable => '网络不可用，请检查连接后重试。';

  @override
  String get coreUpdateErrorDownloadFailedRetry => '下载安装包失败，请稍后重试。';

  @override
  String get coreUpdateErrorChecksumFailed => '安装包校验失败，请稍后重试。';

  @override
  String get coreUpdateErrorChecksumUnreadable => '无法读取安装包校验信息。';

  @override
  String get coreUpdateErrorChecksumMissing => '未找到安装包校验信息。';

  @override
  String get coreUpdateErrorMacFailed => 'macOS 更新失败，请稍后重试。';

  @override
  String get coreUpdateErrorMacNotFound => '没有找到可安装的 macOS 更新。';

  @override
  String get coreUpdateErrorMacDismissed => 'macOS 更新流程已结束，请稍后重试。';

  @override
  String get coreUpdateErrorMacInterrupted => 'macOS 更新流程已中断，请稍后重试。';

  @override
  String get coreUpdateErrorMacLaunchFailed => 'macOS 更新启动失败，请稍后重试。';

  @override
  String get homePageTitle => '首页';

  @override
  String get homeEarningsTotalPrefix => '累计总收益 ';

  @override
  String get homeActivityRecent => '最近活跃';

  @override
  String get homeActivityWeeklySummary => '本周总结';

  @override
  String get homeActivityStreak => '连续记录';

  @override
  String get homeActivityLastSync => '上次同步';

  @override
  String get homeActivityJustNow => '刚刚';

  @override
  String get homeInputHint => '写下你的想法，AI 将自动整理并生成结构化内容...';

  @override
  String get homeUploadImageTooltip => '上传图片';

  @override
  String get homeAddFileTooltip => '添加文件';

  @override
  String get homeMentionTooltip => '提及功能';

  @override
  String homeCharacterCount(Object count) {
    return '$count 字';
  }

  @override
  String get homeSmartGenerate => '智能生成';

  @override
  String get homeGenerating => '整理中';

  @override
  String homeImageChipLabel(Object name) {
    return '图片 · $name';
  }

  @override
  String get homeAttachmentImageLabel => '图片';

  @override
  String get homeAttachmentFileLabel => '文件';

  @override
  String homeAttachmentChipLabel(Object name, Object type) {
    return '$type · $name';
  }

  @override
  String get homeEmptyHint => '暂无内容';

  @override
  String homeSavedPath(Object path) {
    return '已写入当日日报：$path';
  }

  @override
  String homeUpdateAvailable(Object version) {
    return '发现新版本 $version，点击查看更新内容';
  }

  @override
  String get homeUpdateCheckFailed => '更新检测失败';

  @override
  String get homeGlobalSign => '全局签';

  @override
  String get homeClipboardImageError => '无法读取剪贴板图片。';

  @override
  String get homeClipboardTextError => '无法读取剪贴板文字。';

  @override
  String get homeAddImageError => '无法添加图片，请重新选择文件。';

  @override
  String get homeAddAttachmentError => '无法添加附件，请重新选择文件。';

  @override
  String homeImageOversized(Object maxSize, Object names) {
    return '单张图片不能超过 $maxSize：$names。';
  }

  @override
  String homeImageLimitExceeded(Object count, Object max) {
    return '最多添加 $max 张图片，已忽略 $count 张。';
  }

  @override
  String homeImageUnsupportedForAi(Object names) {
    return '这些图片会保存进日报，但不会发送给 AI：$names。';
  }

  @override
  String get homeNoImageToAdd => '没有可添加的图片。';

  @override
  String get homePickImageButton => '选择图片';

  @override
  String get homePickFileButton => '选择文件';

  @override
  String get homeImageNamesSeparator => '、';

  @override
  String homeImageNamesRemaining(Object count, Object names) {
    return '$names 等 $count 张';
  }

  @override
  String get homeAiNoticeNoModel => '未配置可用模型或 AI 返回不可用，本次已使用本地 mock / 简单合并。';

  @override
  String get homeAiNoticeImageUnsupported =>
      '当前智能生成模型未标记支持图像输入，图片已保存进日报但未发送给 AI。';

  @override
  String get homeAiNoticeGlobalSignFailed => '三栏与日报已生成，但全局签 AI 更新失败，全局签内容未变更。';

  @override
  String get homeGlobalSignFallbackDone => '无法调用 AI，已在本地更新全局签，并将完成/取消内容写入当日日报。';

  @override
  String get homeGlobalSignFallbackUpdated =>
      '日报已更新，但全局签 AI 刷新失败，已在本地移除完成/取消项。';

  @override
  String get homeGlobalSignFallbackSaved => '全局签 AI 刷新失败，已在本地保存修改。';

  @override
  String get homeGlobalSignUnconfirmedChanges => '有未确认的变更';

  @override
  String get homeGlobalSignConfirmHint => '完成 / 取消 / 修改后请点击确认';

  @override
  String get homeGlobalSignTooltipUndoComplete => '撤销完成';

  @override
  String get homeGlobalSignTooltipComplete => '完成';

  @override
  String get homeGlobalSignTooltipUndoCancel => '撤销取消';

  @override
  String get homeGlobalSignTooltipCancel => '取消';

  @override
  String get homeGlobalSignTooltipDelete => '删除';

  @override
  String get homeGlobalSignDeleteConfirmTitle => '删除这条全局签？';

  @override
  String get homeGlobalSignDeleteConfirmMessage =>
      '删除后不会写入日报，也不会经过 AI 整理，且无法恢复。';

  @override
  String homeDesktopLevelTitle(Object level, Object percent) {
    return 'Lv.$level 实习生 ($percent%)';
  }

  @override
  String homeActivityCountTimes(Object count) {
    return '$count 次';
  }

  @override
  String homeActivityCountDays(Object count) {
    return '$count 天';
  }

  @override
  String get memoryChatHint => '继续追问你的回忆...';

  @override
  String get memoryEntryHint => '问问你的回忆...';

  @override
  String get memoryEntryTitle => '准备好了，随时开始';

  @override
  String get memoryInputModeMindMapDescription => '以思维导图呈现回答';

  @override
  String get memoryInputModeMindMapLabel => '思维导图';

  @override
  String get memoryInputModeTooltip => '输入模式';

  @override
  String get memoryModelRequestFailed => '模型请求失败。';

  @override
  String memoryMockAnswerEmpty(Object question) {
    return '## AI 回答\n\n我还没有在日报、周报或月报中检索到和「$question」直接相关的记录。你可以换一个更具体的关键词，例如项目名、模块名、问题现象或日期。';
  }

  @override
  String memoryMockAnswerSourceItem(Object snippet, Object title) {
    return '- **$title**：$snippet';
  }

  @override
  String memoryMockAnswerToolStep(
    Object observation,
    Object query,
    Object thought,
    Object toolLabel,
  ) {
    return '- Thought：$thought\n  Act：$toolLabel（$query）\n  Observation：$observation';
  }

  @override
  String memoryMockAnswerWithSources(
    Object question,
    Object sourceList,
    Object toolList,
  ) {
    return '## 使用的工具\n\n$toolList\n\n## 找到的相关回忆\n\n$sourceList\n\n---\n\n## AI 回答\n\n当前未配置可用的回忆书模型，所以先基于本地工具检索给出摘要。上面这些记录可能和「$question」有关，你可以配置回忆书模型后获得更完整的解释、归纳和追问建议。';
  }

  @override
  String get memoryNewConversationTooltip => '开启新对话';

  @override
  String get memoryNoUsableAnswer => '我没有拿到可用回答。';

  @override
  String get memoryPageTitle => '回忆书';

  @override
  String get memoryQuickPromptMonthReport => '查看本月月报';

  @override
  String get memoryQuickPromptTodayDaily => '查看今天日报';

  @override
  String get memoryQuickPromptWeekDaily => '查看本周日报';

  @override
  String get memoryReasoningTitle => '深度思考';

  @override
  String get memoryToolArgumentsLabel => '传入参数';

  @override
  String get memoryToolCallsLimitReached =>
      '工具调用轮次已达到上限。请把问题缩小到具体日期、项目名或关键词后再试。';

  @override
  String get memoryToolLabelGetCurrentDate => '获取当前日期';

  @override
  String get memoryToolLabelKeywordSearch => '关键词搜索';

  @override
  String get memoryToolLabelReadDailyNote => '读取日报';

  @override
  String get memoryToolLabelReadMonthReport => '读取月报';

  @override
  String get memoryToolLabelReadMonthWeeklyNotes => '读取月内周报';

  @override
  String get memoryToolLabelReadWeekDailyNotes => '读取周内日报';

  @override
  String get memoryToolLabelReadWeeklyNote => '读取周报';

  @override
  String get memoryToolLabelSearchDailyNotes => '搜索日报关键词';

  @override
  String get memoryToolLabelSearchMonthlyNotes => '搜索月报关键词';

  @override
  String get memoryToolLabelSearchWeeklyNotes => '搜索周报关键词';

  @override
  String get memoryToolNameLabel => '工具名称';

  @override
  String get memoryToolNoResult => '暂无返回结果';

  @override
  String memoryToolResultCount(Object count) {
    return '$count 条结果';
  }

  @override
  String get memoryToolResultLabel => '返回结果';

  @override
  String get memoryToolResultNone => '无结果';

  @override
  String get memoryToolResultReturned => '已返回';

  @override
  String get memoryWaitingIndicator => '正在思考并调用工具...';

  @override
  String get notesPreviewEmptyHint => '预览区域会随着 Markdown 源码实时刷新';

  @override
  String get notesFimReady => 'AI 实时补全已就绪';

  @override
  String get notesSaved => '已保存';

  @override
  String notesAutoSyncFailedMessage(Object message) {
    return '自动同步失败：$message';
  }

  @override
  String get notesAutoSyncFailedRetry => '自动同步失败，请稍后重试。';

  @override
  String get notesFimPredicting => 'AI 编辑预测中';

  @override
  String get notesFimAcceptHint => 'Tab 全部 · Ctrl+L 单行 · Ctrl+K 单字';

  @override
  String notesFimNotTriggered(Object reason) {
    return 'FIM 未触发：$reason';
  }

  @override
  String notesFimRequestFailed(Object error) {
    return 'FIM 请求失败：$error';
  }

  @override
  String get notesFimNoPrediction => 'FIM 已请求，但没有返回可用预测';

  @override
  String get notesRegenerated => '已重新生成';

  @override
  String notesRegenerateFailedMessage(Object message) {
    return '重新生成失败：$message';
  }

  @override
  String get notesRegenerateFailedRetry => '重新生成失败，请稍后重试。';

  @override
  String get notesImageSelectionCanceled => '已取消选择图片';

  @override
  String get notesImageInserted => '已插入图片';

  @override
  String get notesImageFormatUnsupported => '图片格式不支持，请重新选择文件。';

  @override
  String get notesImageInsertFailed => '无法插入图片，请重新选择文件。';

  @override
  String get notesImagePasted => '已粘贴图片';

  @override
  String get notesClipboardImageFormatUnsupported => '图片格式不支持，请重新复制图片文件。';

  @override
  String get notesClipboardImagePasteFailed => '无法粘贴图片，请重新获取图片后重试。';

  @override
  String get notesClipboardTextReadFailed => '无法读取剪贴板文字。';

  @override
  String get notesClipboardEmpty => '剪贴板中没有可粘贴的内容。';

  @override
  String get notesSelectImage => '选择图片';

  @override
  String get notesNotebookTitle => '笔记本';

  @override
  String notesSearchAllHint(Object kindLabel) {
    return '搜索全部$kindLabel...';
  }

  @override
  String get notesNoMatchingNotes => '没有匹配的便签';

  @override
  String get notesSearchMinChars => '至少输入 2 个字符';

  @override
  String get notesSearching => '正在搜索...';

  @override
  String get notesNoSearchResults => '没有匹配内容';

  @override
  String get notesSwitchKindSemantics => '切换日报/周报/月报';

  @override
  String get notesSwitchNoteType => '切换笔记类型';

  @override
  String get notesKindDailyDescription => '每日记录';

  @override
  String get notesKindWeeklyDescription => '阶段整理';

  @override
  String get notesKindMonthlyDescription => '月度沉淀';

  @override
  String get notesInsertImageTooltip => '插入图片';

  @override
  String get notesRegenerateTooltip => '重新生成';

  @override
  String get notesEditorHint => '# 开始编辑 Markdown...';

  @override
  String get notesWorkspaceModeEdit => '编辑';

  @override
  String get notesWorkspaceModeSplit => '分栏';

  @override
  String get notesWorkspaceModePreview => '预览';

  @override
  String get settingsProvidersSearchHint => '搜索供应商';

  @override
  String get settingsNoProviders => '暂无供应商';

  @override
  String get settingsNoMatchingProviders => '未找到匹配的供应商';

  @override
  String get settingsAdd => '添加';

  @override
  String get settingsProviderName => '名称';

  @override
  String get settingsApiPath => 'API 路径';

  @override
  String get settingsAddModelFirst => '请先添加至少一个模型。';

  @override
  String settingsModelAdded(Object modelName) {
    return '已添加 $modelName';
  }

  @override
  String get settingsModelRemoved => '已移除模型';

  @override
  String get settingsFetchModelsFailed => '获取模型失败，请检查供应商配置。';

  @override
  String get settingsDeleteProvider => '删除供应商';

  @override
  String get settingsDeleteProviderConfirm => '确定要删除该供应商吗？此操作不可撤销。';

  @override
  String get settingsTestingStream => '流式测试中';

  @override
  String get settingsTesting => '测试中';

  @override
  String get settingsConnectionTestFailed => '连接测试失败';

  @override
  String get settingsTestConnection => '测试连接';

  @override
  String get settingsUseStreaming => '使用流式';

  @override
  String get settingsTest => '测试';

  @override
  String get settingsConnectionSucceeded => '连接成功';

  @override
  String get settingsConnectionFailed => '连接失败';

  @override
  String get settingsSelectModel => '选择模型';

  @override
  String get settingsTestSucceeded => '测试成功';

  @override
  String get settingsSearchModelsOrProviders => '搜索模型或服务商';

  @override
  String get settingsNoMatchingModels => '没有匹配的模型';

  @override
  String settingsProviderModelsTitle(Object providerName) {
    return '$providerName 模型';
  }

  @override
  String get settingsSelectModelsSubtitle => '选择要添加到当前提供商的模型';

  @override
  String get settingsRefresh => '刷新';

  @override
  String get settingsSearchModels => '搜索模型';

  @override
  String get settingsNoModelsFetched => '没有获取到模型';

  @override
  String get settingsFetchingModels => '正在获取模型...';

  @override
  String get settingsRetry => '重试';

  @override
  String get settingsOtherModels => '其他模型';

  @override
  String get settingsModels => '模型';

  @override
  String get settingsFetching => '获取中';

  @override
  String get settingsFetchModels => '获取模型';

  @override
  String get settingsAddModel => '添加模型';

  @override
  String get settingsNoModels => '暂无模型';

  @override
  String get settingsAddModelViaButton => '点击右上角添加';

  @override
  String get settingsEditModel => '编辑模型';

  @override
  String get settingsDeleteModel => '删除模型';

  @override
  String get settingsAddProvider => '添加供应商';

  @override
  String get settingsEnabled => '启用';

  @override
  String get settingsModelId => '模型 ID';

  @override
  String get settingsModelName => '模型名称';

  @override
  String get settingsEditModelSubtitle => '调整模型展示名称、输入类型与可用能力';

  @override
  String get settingsModelType => '模型类型';

  @override
  String get settingsModelTypeChat => '聊天';

  @override
  String get settingsModelTypeCompletion => '补全';

  @override
  String get settingsInputMode => '输入模式';

  @override
  String get settingsInputModeText => '文本';

  @override
  String get settingsInputModeImage => '图片';

  @override
  String get settingsCapability => '能力';

  @override
  String get settingsCapabilityTools => '工具';

  @override
  String get settingsCapabilityReasoning => '推理';

  @override
  String get settingsCompletionProtocol => '补全协议';

  @override
  String get settingsCopied => '已复制';

  @override
  String get settingsCopyModelId => '复制模型 ID';

  @override
  String get settingsConnectionSettings => '连接设置';

  @override
  String get settingsEnableCloudSync => '启用云同步';

  @override
  String get settingsWebdavUrl => 'WebDAV 地址';

  @override
  String get settingsAccount => '账号';

  @override
  String get settingsSyncStrategy => '同步策略';

  @override
  String get settingsSyncOnStartup => '应用启动时自动同步';

  @override
  String get settingsRealTimeSync => '实时同步';

  @override
  String get settingsLastFullSync => '最近一次全量同步';

  @override
  String get settingsDeleteCanceled => '已取消删除，未执行删除项';

  @override
  String get settingsDeleteModifyConflictsSkipped => '已跳过删除修改冲突，未处理冲突项';

  @override
  String get settingsSyncPendingItems => '仍有待确认项，请重新同步。';

  @override
  String get settingsUrlInvalid => '请输入完整 URL';

  @override
  String get settingsUrlSchemeUnsupported => '仅支持 http/https';

  @override
  String get settingsNotSyncedYet => '尚未同步';

  @override
  String get settingsPasswordAppToken => '密码/应用令牌';

  @override
  String get settingsConfirmDeleteSync => '确认删除同步';

  @override
  String get settingsDeleteSyncDescription => '检测到删除操作，确认后将同步删除对应文件。';

  @override
  String get settingsWillDeleteLocal => '将删除本地文件';

  @override
  String get settingsWillDeleteRemote => '将删除远端文件';

  @override
  String get settingsConfirmDeleteAndSync => '确认删除并同步';

  @override
  String get settingsUnhandledItems => '仍有未处理项';

  @override
  String settingsUnhandledItemsMessage(Object count) {
    return '仍有 $count 个文件未选择处理方式，将自动视为“跳过此项”，是否继续？';
  }

  @override
  String get settingsBackToSelection => '返回选择';

  @override
  String get settingsContinue => '继续';

  @override
  String get settingsDeleteConflictDetected => '检测到删除冲突';

  @override
  String get settingsDeleteConflictDescription =>
      '以下文件在一端已删除，另一端已修改，请选择最终保留的结果。';

  @override
  String get settingsLocalModified => '本地：已修改';

  @override
  String get settingsLocalDeleted => '本地：已删除';

  @override
  String get settingsRemoteDeleted => '远端：已删除';

  @override
  String get settingsRemoteModified => '远端：已修改';

  @override
  String get settingsKeepLocalVersion => '保留本地版本';

  @override
  String get settingsKeepLocalVersionTooltip => '上传本地文件到远端，恢复远端文件。';

  @override
  String get settingsKeepLocalDeletion => '保留本地删除';

  @override
  String get settingsKeepLocalDeletionTooltip => '删除远端文件，与本地删除状态保持一致。';

  @override
  String get settingsKeepRemoteDeletion => '保留远端删除';

  @override
  String get settingsKeepRemoteDeletionTooltip => '删除本地文件，保持远端已删除的状态。';

  @override
  String get settingsKeepRemoteVersion => '保留远端版本';

  @override
  String get settingsKeepRemoteVersionTooltip => '下载远端文件，恢复本地文件。';

  @override
  String get settingsSkip => '跳过';

  @override
  String get settingsSkipTooltip => '本次不同步该文件，下次同步时仍会提示处理。';

  @override
  String get settingsStatsTotalLabel => '共';

  @override
  String settingsStatsConflictCount(Object count) {
    return '$count 个冲突';
  }

  @override
  String get settingsStatsHandledLabel => '已处理';

  @override
  String settingsStatsHandledValue(Object count) {
    return '$count 个';
  }

  @override
  String get settingsStatsRemainingLabel => '剩余';

  @override
  String settingsStatsRemainingValue(Object count) {
    return '$count 个';
  }

  @override
  String get settingsSkipAll => '全部跳过';

  @override
  String get settingsContinueBySelection => '按选择继续';

  @override
  String get settingsSyncActions => '同步操作';

  @override
  String get settingsSyncing => '同步中';

  @override
  String get settingsManualSync => '手动同步';

  @override
  String get settingsStatsAll => '全部';

  @override
  String get settingsStatsRecent30 => '最近 30 天';

  @override
  String get settingsStatsRecent30Days => '最近30天';

  @override
  String get settingsStatsLastMonth => '上个月';

  @override
  String get settingsStatsLastQuarter => '上个季度';

  @override
  String get settingsStatsCustom => '自定义';

  @override
  String settingsStatsDateRange(Object end, Object start) {
    return '$start 至 $end';
  }

  @override
  String get settingsStatsYearlyHeatmap => '年度热力图';

  @override
  String get settingsStatsOverview => '总览';

  @override
  String get settingsStatsUsageTrend => '用量趋势';

  @override
  String get settingsStatsSummaries => '总结数';

  @override
  String get settingsStatsFimCompletions => '编辑补全次数';

  @override
  String get settingsStatsTotalRecords => '总记录数';

  @override
  String get settingsStatsDailyNotes => '日报数';

  @override
  String get settingsStatsWeeklyNotes => '周报数';

  @override
  String get settingsStatsMonthlyNotes => '月报数';

  @override
  String get settingsStatsInputTokens => '输入 Tokens';

  @override
  String get settingsStatsOutputTokens => '输出 Tokens';

  @override
  String get settingsStatsCachedTokens => '缓存 Tokens';

  @override
  String get settingsStatsAppLaunches => '应用启动次数';

  @override
  String settingsStatsMonthLabel(Object month) {
    return '$month月';
  }

  @override
  String get settingsStatsWeekdayMon => '一';

  @override
  String get settingsStatsWeekdayWed => '三';

  @override
  String get settingsStatsWeekdayFri => '五';

  @override
  String get settingsStatsNoUsageRecords => '暂无模型调用记录';

  @override
  String get settingsStatsOther => '其他';

  @override
  String get settingsStatsCustomRangeTitle => '自定义时间段';

  @override
  String get settingsStatsStart => '开始';

  @override
  String get settingsStatsEnd => '结束';

  @override
  String get settingsStatsApply => '应用';

  @override
  String get settingsStatsWeekdayTue => '周二';

  @override
  String get settingsStatsWeekdayThu => '周四';

  @override
  String get settingsStatsWeekdaySat => '周六';

  @override
  String get settingsStatsWeekdaySun => '周日';

  @override
  String settingsScanFailed(Object error) {
    return '扫描失败：$error';
  }

  @override
  String settingsCleanFailed(Object error) {
    return '清理失败：$error';
  }

  @override
  String settingsCleanPartialFailed(Object deletedCount, Object failedCount) {
    return '已清理 $deletedCount 张，$failedCount 张删除失败。';
  }

  @override
  String get settingsCleanNoFiles => '图片引用已发生变化，没有删除任何文件。';

  @override
  String settingsCleanSkipped(Object deletedCount, Object skippedCount) {
    return '已清理 $deletedCount 张图片，$skippedCount 张因引用变化已保留。';
  }

  @override
  String settingsCleanDone(Object deletedCount, Object freedSize) {
    return '已清理 $deletedCount 张图片，释放 $freedSize。';
  }

  @override
  String get settingsCleaning => '正在清理';

  @override
  String get settingsScanning => '正在扫描';

  @override
  String get settingsImageAttachments => '图片附件';

  @override
  String get settingsRescan => '重新扫描';

  @override
  String get settingsCleanImages => '清理图片';

  @override
  String get settingsNoStats => '暂无统计信息';

  @override
  String get settingsAllImages => '全部图片';

  @override
  String get settingsStillInUse => '仍在使用';

  @override
  String get settingsCleanable => '可以清理';

  @override
  String settingsUnusedCount(Object count) {
    return '未使用 $count';
  }

  @override
  String get settingsSelectAll => '全选';

  @override
  String get settingsDeselectAll => '取消全选';

  @override
  String settingsSelectedSummary(Object count, Object size) {
    return '已选 $count · $size';
  }

  @override
  String get settingsConfirmDelete => '确认删除';

  @override
  String get settingsPreview => '预览';

  @override
  String get settingsPreviewFailed => '无法预览这张图片';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSectionPreferences => '偏好设置';

  @override
  String get settingsSectionProviders => '供应商';

  @override
  String get settingsSectionModels => '默认模型';

  @override
  String get settingsSectionHotkeys => '快捷键';

  @override
  String get settingsSectionCloudSync => '云同步';

  @override
  String get settingsSectionStorage => '存储管理';

  @override
  String get settingsSectionStats => '统计';

  @override
  String get settingsSectionAbout => '关于';

  @override
  String get settingsImageFileType => '图片';

  @override
  String get settingsImageNotSelected => '未选择';

  @override
  String settingsImagePickFailed(Object error) {
    return '选择图片失败: $error';
  }

  @override
  String get settingsPersonalInfoTitle => '个人信息';

  @override
  String get settingsDailyWorkHours => '每日工作时长';

  @override
  String get settingsHoursSuffix => '小时';

  @override
  String get settingsDailySalary => '日薪';

  @override
  String get settingsIndustry => '所在行业';

  @override
  String get settingsFontDisplayTitle => '字体与显示';

  @override
  String get settingsAppFont => '应用字体';

  @override
  String get settingsFontSize => '字体大小';

  @override
  String get settingsMarkdownHighlight => 'Markdown 语法高亮';

  @override
  String get settingsBehaviorTitle => '行为与启动';

  @override
  String get settingsAutoStart => '开机自启动';

  @override
  String get settingsShowUpdates => '显示更新';

  @override
  String get settingsApiLog => '记录 API 网络日志';

  @override
  String get settingsWallpaperTitle => '壁纸';

  @override
  String get settingsWallpaperMode => '模式';

  @override
  String get settingsWallpaperModeDefault => '默认背景';

  @override
  String get settingsWallpaperModeImage => '本地图片';

  @override
  String get settingsWallpaperModeSolid => '纯色';

  @override
  String get settingsSelectImage => '选择图片';

  @override
  String get settingsWallpaperFill => '填充';

  @override
  String get settingsWallpaperFillStretch => '拉伸';

  @override
  String get settingsWallpaperFillCover => '覆盖';

  @override
  String get settingsWallpaperFillCenter => '居中';

  @override
  String get settingsBackgroundColor => '背景颜色';

  @override
  String get settingsOpacity => '不透明度';

  @override
  String get settingsBlur => '模糊度';

  @override
  String get settingsMaskOpacity => '蒙版浓度';

  @override
  String get settingsTransparentControls => '透明控件模式';

  @override
  String get settingsControlOpacity => '控件不透明度';

  @override
  String get settingsShowBorders => '保留卡片描边';

  @override
  String get settingsTextContrast => '文字颜色加深';

  @override
  String get settingsTrayTitle => '托盘';

  @override
  String get settingsShowTrayIcon => '显示托盘图标';

  @override
  String get settingsCloseToTray => '关闭时最小化到托盘';

  @override
  String get settingsDataSaveTitle => '数据保存';

  @override
  String get settingsComponentTitle => '组件设置';

  @override
  String get settingsShowDesktopWidget => '显示桌面组件';

  @override
  String get settingsOrbMode => '桌面组件圆球模式';

  @override
  String get settingsWidgetWallpaperTitle => '组件壁纸';

  @override
  String get settingsWidgetWallpaperModeDefaultWhite => '默认白色';

  @override
  String get settingsPromptTitle => '提示词';

  @override
  String get settingsHomeSections => '首页栏目';

  @override
  String get settingsDailyMergePrompt => '日报整理';

  @override
  String get settingsGlobalSignPrompt => '全局签整理';

  @override
  String get settingsEditDailyMergePromptTitle => '编辑日报整理提示词';

  @override
  String get settingsDailyMergePromptHint => '输入日报整理 Prompt...';

  @override
  String get settingsEditGlobalSignPromptTitle => '编辑全局签提示词';

  @override
  String get settingsGlobalSignPromptHint => '输入全局签整理 Prompt...';

  @override
  String get settingsVariableCurrentDate => '当前日期';

  @override
  String get settingsVariableExistingDailyContent => '已有日报内容';

  @override
  String get settingsVariableRawInput => '新增随手记录';

  @override
  String get settingsVariableIndustry => '用户所在行业';

  @override
  String get settingsVariableDailyContent => '当日日报内容';

  @override
  String get settingsVariableGlobalSignJson => '当前全局签 JSON';

  @override
  String get settingsMemoryTitle => '回忆书检索';

  @override
  String get settingsMemorySearchLimit => '回忆书单轮最大搜索次数';

  @override
  String get settingsTimesSuffix => '次';

  @override
  String get settingsMemoryResultMaxChars => '单条结果返回最大字符数';

  @override
  String get settingsCharsSuffix => '字';

  @override
  String get settingsMemoryWeekDailyLimit => '连续日报读取最大数量';

  @override
  String get settingsItemsSuffix => '条';

  @override
  String get settingsMemoryKeywordSearchLimit => '关键词搜索结果最大数量';

  @override
  String get settingsMemoryKeywordBefore => '命中关键词截取前最大字符数';

  @override
  String get settingsMemoryKeywordAfter => '命中关键词截取后最大字符数';

  @override
  String settingsConfigFileLabel(Object path) {
    return '配置文件：$path';
  }

  @override
  String get settingsPlatformNotSupported => '当前平台暂不支持';

  @override
  String get settingsDataMigrationComplete => '数据迁移完成';

  @override
  String get settingsDataMigrationDetail =>
      '已成功切换至新的数据目录。\n确认数据正常后，可删除原目录以释放存储空间。';

  @override
  String get settingsSectionTitleHeader => '标题';

  @override
  String get settingsAiInstructionHeader => 'AI 说明';

  @override
  String get settingsSectionTitleHint => '栏目标题';

  @override
  String get settingsSectionInstructionHint => '描述分类规则';

  @override
  String get settingsFimReady => 'AI 实时补全已就绪';

  @override
  String get settingsFimPredicting => 'AI 补全预测中';

  @override
  String get settingsFimAcceptHint => 'Tab 全部 · Ctrl+L 单行 · Ctrl+K 单字';

  @override
  String settingsFimNotTriggered(Object reason) {
    return 'FIM 未触发：$reason';
  }

  @override
  String settingsFimRequestFailed(Object error) {
    return 'FIM 请求失败：$error';
  }

  @override
  String get settingsFimNoPrediction => 'FIM 已请求，但没有返回可用预测';

  @override
  String get settingsSelectThisFolder => '选择此文件夹';

  @override
  String get settingsSaveDirectory => '保存目录';

  @override
  String get settingsDataDirectoryHint => '当前保存目录';

  @override
  String get settingsSelectMigrateDirectory => '选择并迁移目录';

  @override
  String get settingsRestoreDefaultDirectory => '恢复默认目录';

  @override
  String get settingsSystemDefault => '系统默认';

  @override
  String get settingsResetFont => '重置字体';

  @override
  String get settingsSelectFont => '选择字体';

  @override
  String get settingsSearchSystemFonts => '搜索系统字体';

  @override
  String get settingsNoMatchingFonts => '没有匹配的字体';

  @override
  String get settingsAppearanceMode => '外观模式';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsProtocol => '协议';

  @override
  String get settingsDisabled => '禁用';

  @override
  String get settingsEmptyProviderDetails => '添加供应商后在这里编辑配置';

  @override
  String get settingsSelectColor => '选择颜色';

  @override
  String get settingsModelIntelligent => '智能生成模型';

  @override
  String get settingsModelIntelligentDesc => '用于首页随手记录后的结构化整理和日报合并。';

  @override
  String get settingsModelEditCompletion => '编辑补全模型';

  @override
  String get settingsModelEditCompletionDesc =>
      '用于便签页补全。模型类型包含补全时，默认按 completions FIM 调用。';

  @override
  String get settingsModelMemoryBook => '回忆书模型';

  @override
  String get settingsModelMemoryBookDesc => '用于回忆书问答和历史记录检索回答。';

  @override
  String get settingsModelUnset => '未';

  @override
  String get settingsModelSet => '已';

  @override
  String get settingsNoModelSelected => '未选择模型';

  @override
  String get settingsSelectModelByProvider => '按供应商选择默认模型';

  @override
  String get settingsNotSelected => '未选择';

  @override
  String get settingsGlobalHotkeysTitle => '全局快捷键';

  @override
  String get settingsShowHidePage => '显示/隐藏页面';

  @override
  String get settingsReset => '重置';

  @override
  String get settingsInputShortcutsTitle => '输入快捷键';

  @override
  String get settingsSendMessage => '发送消息';

  @override
  String get settingsHotkeyNotSupported => '暂不支持这个按键';

  @override
  String get settingsHotkeyNeedModifiersMac => '需包含 Cmd、Ctrl、Option 或 Shift';

  @override
  String get settingsHotkeyNeedModifiersWin => '需包含 Ctrl、Alt、Shift 或 Win';

  @override
  String get settingsHotkeyPressHint => '请按下快捷键';

  @override
  String get settingsHotkeyNotSet => '未设置';

  @override
  String get settingsAppTagline => 'AI 智能便签与日报生成工具';

  @override
  String get settingsCheckForUpdates => '检查更新';

  @override
  String get settingsWebsite => '官网';

  @override
  String get settingsLicense => '许可证';

  @override
  String get settingsJoinQQGroup => '加入QQ群';

  @override
  String get settingsCheckingForUpdates => '正在检查更新...';

  @override
  String get settingsUpdateContentUnavailable => '暂时无法读取更新内容';

  @override
  String get settingsAlreadyUpToDate => '当前已是最新版本';

  @override
  String get settingsUpdateCheckFailed => '暂时无法检查更新，请稍后重试';

  @override
  String get settingsVersion => '版本';

  @override
  String get settingsSystem => '系统';

  @override
  String get settingsUnknown => '未知';

  @override
  String settingsSelectModelTitled(Object title) {
    return '选择$title';
  }

  @override
  String get notesKindDaily => '日报';

  @override
  String get notesKindWeekly => '周报';

  @override
  String get notesKindMonthly => '月报';

  @override
  String get settingsMigrationErrorNested => '保存目录不能选择当前数据目录的子目录。';

  @override
  String get settingsMigrationErrorIsFile => '保存目录不能是一个文件。';

  @override
  String get settingsMigrationErrorMacAccess => '无法保存 macOS 文件夹访问授权，请重新选择保存目录。';

  @override
  String settingsImageUnsupportedFormat(Object extension) {
    return '不支持的图片格式: $extension';
  }

  @override
  String get settingsImageSourceMissing => '源图片不存在';

  @override
  String get settingsProviderApiKeyEmpty => '供应商 API Key 为空。';

  @override
  String get settingsWeeklyReportPrompt => '周报整理';

  @override
  String get settingsEditWeeklyReportPromptTitle => '编辑周报整理提示词';

  @override
  String get settingsWeeklyReportPromptHint => '输入周报整理 Prompt...';

  @override
  String get settingsVariablePeriodLabel => '周报周期';

  @override
  String get settingsVariableSourceMarkdown => '本周日报内容';

  @override
  String get memoryToolLabelResolveIsoWeek => '获取周起止日期';

  @override
  String get memoryToolLabelRunToolBatch => '批量执行工具';

  @override
  String get memoryToolLabelRunToolSequence => '顺序执行工具';

  @override
  String get memoryImageCountLimit => '最多添加 4 张图片。';

  @override
  String get memoryImageInvalid => '仅支持 5 MB 以内的 png、jpg、webp、gif 图片。';

  @override
  String get memoryImageModelUnsupported => '当前回忆模型不支持图片输入。';

  @override
  String get memoryImageSaveFailed => '图片保存失败，请重试。';
}
