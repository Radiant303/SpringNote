import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @actionCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get actionCancel;

  /// No description provided for @actionSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get actionSave;

  /// No description provided for @actionClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get actionClose;

  /// No description provided for @actionConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get actionConfirm;

  /// No description provided for @actionDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get actionDelete;

  /// No description provided for @actionRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get actionRestore;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @languageZh.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get languageZh;

  /// No description provided for @languageEn.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @coreStartupFailedTitle.
  ///
  /// In zh, this message translates to:
  /// **'SpringNote 启动失败'**
  String get coreStartupFailedTitle;

  /// No description provided for @coreAutoSyncIssueMessage.
  ///
  /// In zh, this message translates to:
  /// **'自动同步遇到问题，请手动同步'**
  String get coreAutoSyncIssueMessage;

  /// No description provided for @coreSidebarHomeLabel.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get coreSidebarHomeLabel;

  /// No description provided for @coreSidebarNotesLabel.
  ///
  /// In zh, this message translates to:
  /// **'便签'**
  String get coreSidebarNotesLabel;

  /// No description provided for @coreSidebarMemoryLabel.
  ///
  /// In zh, this message translates to:
  /// **'回忆书'**
  String get coreSidebarMemoryLabel;

  /// No description provided for @coreSidebarSettingsLabel.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get coreSidebarSettingsLabel;

  /// No description provided for @coreCodeCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get coreCodeCopy;

  /// No description provided for @coreCodeCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get coreCodeCopied;

  /// No description provided for @coreTreeGenerating.
  ///
  /// In zh, this message translates to:
  /// **'生成中…'**
  String get coreTreeGenerating;

  /// No description provided for @coreTreeInlineLimitHint.
  ///
  /// In zh, this message translates to:
  /// **'内联视图最多显示 {limit} 个节点，其余 {hidden} 个请通过全屏查看'**
  String coreTreeInlineLimitHint(Object hidden, Object limit);

  /// No description provided for @coreTreeExitFullscreen.
  ///
  /// In zh, this message translates to:
  /// **'退出全屏'**
  String get coreTreeExitFullscreen;

  /// No description provided for @coreTreeFullscreen.
  ///
  /// In zh, this message translates to:
  /// **'全屏查看'**
  String get coreTreeFullscreen;

  /// No description provided for @coreTreeZoomIn.
  ///
  /// In zh, this message translates to:
  /// **'放大'**
  String get coreTreeZoomIn;

  /// No description provided for @coreTreeZoomOut.
  ///
  /// In zh, this message translates to:
  /// **'缩小'**
  String get coreTreeZoomOut;

  /// No description provided for @coreTreeFitAll.
  ///
  /// In zh, this message translates to:
  /// **'适应全图'**
  String get coreTreeFitAll;

  /// No description provided for @coreUpdateDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本'**
  String get coreUpdateDialogTitle;

  /// No description provided for @coreUpdateCurrentVersionLabel.
  ///
  /// In zh, this message translates to:
  /// **'当前版本'**
  String get coreUpdateCurrentVersionLabel;

  /// No description provided for @coreUpdateLatestVersionLabel.
  ///
  /// In zh, this message translates to:
  /// **'最新版本'**
  String get coreUpdateLatestVersionLabel;

  /// No description provided for @coreUpdateChangeTimeLabel.
  ///
  /// In zh, this message translates to:
  /// **'更新时间'**
  String get coreUpdateChangeTimeLabel;

  /// No description provided for @coreUpdateChangeTimeNotProvided.
  ///
  /// In zh, this message translates to:
  /// **'未提供'**
  String get coreUpdateChangeTimeNotProvided;

  /// No description provided for @coreUpdateChangelogTitle.
  ///
  /// In zh, this message translates to:
  /// **'更新内容'**
  String get coreUpdateChangelogTitle;

  /// No description provided for @coreUpdateChangelogEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无更新内容。'**
  String get coreUpdateChangelogEmpty;

  /// No description provided for @coreUpdateChangelogLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新内容加载失败。'**
  String get coreUpdateChangelogLoadFailed;

  /// No description provided for @coreUpdatePreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在准备更新...'**
  String get coreUpdatePreparing;

  /// No description provided for @coreUpdateDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载安装包 {received}'**
  String coreUpdateDownloading(Object received);

  /// No description provided for @coreUpdateDownloadingProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在下载安装包 {received} / {total}'**
  String coreUpdateDownloadingProgress(Object received, Object total);

  /// No description provided for @coreUpdateVerifying.
  ///
  /// In zh, this message translates to:
  /// **'正在校验安装包...'**
  String get coreUpdateVerifying;

  /// No description provided for @coreUpdateExtracting.
  ///
  /// In zh, this message translates to:
  /// **'正在解压更新...'**
  String get coreUpdateExtracting;

  /// No description provided for @coreUpdateExtractingProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在解压更新 {percent}%'**
  String coreUpdateExtractingProgress(Object percent);

  /// No description provided for @coreUpdateInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在安装更新...'**
  String get coreUpdateInstalling;

  /// No description provided for @coreUpdateLaunchingWindows.
  ///
  /// In zh, this message translates to:
  /// **'正在启动安装器，SpringNote 即将退出并重启...'**
  String get coreUpdateLaunchingWindows;

  /// No description provided for @coreUpdateLaunching.
  ///
  /// In zh, this message translates to:
  /// **'正在重启并替换为新版本...'**
  String get coreUpdateLaunching;

  /// No description provided for @coreUpdateButtonPreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在准备更新'**
  String get coreUpdateButtonPreparing;

  /// No description provided for @coreUpdateButtonInstallNow.
  ///
  /// In zh, this message translates to:
  /// **'立即更新'**
  String get coreUpdateButtonInstallNow;

  /// No description provided for @coreUpdateLaunchFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新启动失败，请稍后重试。'**
  String get coreUpdateLaunchFailed;

  /// No description provided for @coreUpdateErrorUnsupportedPlatform.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂不支持自动更新。'**
  String get coreUpdateErrorUnsupportedPlatform;

  /// No description provided for @coreUpdateErrorUpdaterMissing.
  ///
  /// In zh, this message translates to:
  /// **'更新助手缺失，请下载最新安装包手动更新。'**
  String get coreUpdateErrorUpdaterMissing;

  /// No description provided for @coreUpdateErrorDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载安装包失败 ({status})'**
  String coreUpdateErrorDownloadFailed(Object status);

  /// No description provided for @coreUpdateErrorDownloadTimeout.
  ///
  /// In zh, this message translates to:
  /// **'下载更新超时，请稍后重试。'**
  String get coreUpdateErrorDownloadTimeout;

  /// No description provided for @coreUpdateErrorNetworkUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'网络不可用，请检查连接后重试。'**
  String get coreUpdateErrorNetworkUnavailable;

  /// No description provided for @coreUpdateErrorDownloadFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'下载安装包失败，请稍后重试。'**
  String get coreUpdateErrorDownloadFailedRetry;

  /// No description provided for @coreUpdateErrorChecksumFailed.
  ///
  /// In zh, this message translates to:
  /// **'安装包校验失败，请稍后重试。'**
  String get coreUpdateErrorChecksumFailed;

  /// No description provided for @coreUpdateErrorChecksumUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'无法读取安装包校验信息。'**
  String get coreUpdateErrorChecksumUnreadable;

  /// No description provided for @coreUpdateErrorChecksumMissing.
  ///
  /// In zh, this message translates to:
  /// **'未找到安装包校验信息。'**
  String get coreUpdateErrorChecksumMissing;

  /// No description provided for @coreUpdateErrorMacFailed.
  ///
  /// In zh, this message translates to:
  /// **'macOS 更新失败，请稍后重试。'**
  String get coreUpdateErrorMacFailed;

  /// No description provided for @coreUpdateErrorMacNotFound.
  ///
  /// In zh, this message translates to:
  /// **'没有找到可安装的 macOS 更新。'**
  String get coreUpdateErrorMacNotFound;

  /// No description provided for @coreUpdateErrorMacDismissed.
  ///
  /// In zh, this message translates to:
  /// **'macOS 更新流程已结束，请稍后重试。'**
  String get coreUpdateErrorMacDismissed;

  /// No description provided for @coreUpdateErrorMacInterrupted.
  ///
  /// In zh, this message translates to:
  /// **'macOS 更新流程已中断，请稍后重试。'**
  String get coreUpdateErrorMacInterrupted;

  /// No description provided for @coreUpdateErrorMacLaunchFailed.
  ///
  /// In zh, this message translates to:
  /// **'macOS 更新启动失败，请稍后重试。'**
  String get coreUpdateErrorMacLaunchFailed;

  /// No description provided for @homePageTitle.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get homePageTitle;

  /// No description provided for @homeEarningsTotalPrefix.
  ///
  /// In zh, this message translates to:
  /// **'累计总收益 '**
  String get homeEarningsTotalPrefix;

  /// No description provided for @homeActivityRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近活跃'**
  String get homeActivityRecent;

  /// No description provided for @homeActivityWeeklySummary.
  ///
  /// In zh, this message translates to:
  /// **'本周总结'**
  String get homeActivityWeeklySummary;

  /// No description provided for @homeActivityStreak.
  ///
  /// In zh, this message translates to:
  /// **'连续记录'**
  String get homeActivityStreak;

  /// No description provided for @homeActivityLastSync.
  ///
  /// In zh, this message translates to:
  /// **'上次同步'**
  String get homeActivityLastSync;

  /// No description provided for @homeActivityJustNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get homeActivityJustNow;

  /// No description provided for @homeInputHint.
  ///
  /// In zh, this message translates to:
  /// **'写下你的想法，AI 将自动整理并生成结构化内容...'**
  String get homeInputHint;

  /// No description provided for @homeUploadImageTooltip.
  ///
  /// In zh, this message translates to:
  /// **'上传图片'**
  String get homeUploadImageTooltip;

  /// No description provided for @homeAddFileTooltip.
  ///
  /// In zh, this message translates to:
  /// **'添加文件'**
  String get homeAddFileTooltip;

  /// No description provided for @homeMentionTooltip.
  ///
  /// In zh, this message translates to:
  /// **'提及功能'**
  String get homeMentionTooltip;

  /// No description provided for @homeCharacterCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 字'**
  String homeCharacterCount(Object count);

  /// No description provided for @homeSmartGenerate.
  ///
  /// In zh, this message translates to:
  /// **'智能生成'**
  String get homeSmartGenerate;

  /// No description provided for @homeGenerating.
  ///
  /// In zh, this message translates to:
  /// **'整理中'**
  String get homeGenerating;

  /// No description provided for @homeImageChipLabel.
  ///
  /// In zh, this message translates to:
  /// **'图片 · {name}'**
  String homeImageChipLabel(Object name);

  /// No description provided for @homeAttachmentImageLabel.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get homeAttachmentImageLabel;

  /// No description provided for @homeAttachmentFileLabel.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get homeAttachmentFileLabel;

  /// No description provided for @homeAttachmentChipLabel.
  ///
  /// In zh, this message translates to:
  /// **'{type} · {name}'**
  String homeAttachmentChipLabel(Object name, Object type);

  /// No description provided for @homeEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'暂无内容'**
  String get homeEmptyHint;

  /// No description provided for @homeSavedPath.
  ///
  /// In zh, this message translates to:
  /// **'已写入当日日报：{path}'**
  String homeSavedPath(Object path);

  /// No description provided for @homeUpdateAvailable.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本 {version}，点击查看更新内容'**
  String homeUpdateAvailable(Object version);

  /// No description provided for @homeUpdateCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新检测失败'**
  String get homeUpdateCheckFailed;

  /// No description provided for @homeGlobalSign.
  ///
  /// In zh, this message translates to:
  /// **'全局签'**
  String get homeGlobalSign;

  /// No description provided for @homeClipboardImageError.
  ///
  /// In zh, this message translates to:
  /// **'无法读取剪贴板图片。'**
  String get homeClipboardImageError;

  /// No description provided for @homeClipboardTextError.
  ///
  /// In zh, this message translates to:
  /// **'无法读取剪贴板文字。'**
  String get homeClipboardTextError;

  /// No description provided for @homeAddImageError.
  ///
  /// In zh, this message translates to:
  /// **'无法添加图片，请重新选择文件。'**
  String get homeAddImageError;

  /// No description provided for @homeAddAttachmentError.
  ///
  /// In zh, this message translates to:
  /// **'无法添加附件，请重新选择文件。'**
  String get homeAddAttachmentError;

  /// No description provided for @homeImageOversized.
  ///
  /// In zh, this message translates to:
  /// **'单张图片不能超过 {maxSize}：{names}。'**
  String homeImageOversized(Object maxSize, Object names);

  /// No description provided for @homeImageLimitExceeded.
  ///
  /// In zh, this message translates to:
  /// **'最多添加 {max} 张图片，已忽略 {count} 张。'**
  String homeImageLimitExceeded(Object count, Object max);

  /// No description provided for @homeImageUnsupportedForAi.
  ///
  /// In zh, this message translates to:
  /// **'这些图片会保存进日报，但不会发送给 AI：{names}。'**
  String homeImageUnsupportedForAi(Object names);

  /// No description provided for @homeNoImageToAdd.
  ///
  /// In zh, this message translates to:
  /// **'没有可添加的图片。'**
  String get homeNoImageToAdd;

  /// No description provided for @homePickImageButton.
  ///
  /// In zh, this message translates to:
  /// **'选择图片'**
  String get homePickImageButton;

  /// No description provided for @homePickFileButton.
  ///
  /// In zh, this message translates to:
  /// **'选择文件'**
  String get homePickFileButton;

  /// No description provided for @homeImageNamesSeparator.
  ///
  /// In zh, this message translates to:
  /// **'、'**
  String get homeImageNamesSeparator;

  /// No description provided for @homeImageNamesRemaining.
  ///
  /// In zh, this message translates to:
  /// **'{names} 等 {count} 张'**
  String homeImageNamesRemaining(Object count, Object names);

  /// No description provided for @homeAiNoticeNoModel.
  ///
  /// In zh, this message translates to:
  /// **'未配置可用模型或 AI 返回不可用，本次已使用本地 mock / 简单合并。'**
  String get homeAiNoticeNoModel;

  /// No description provided for @homeAiNoticeImageUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前智能生成模型未标记支持图像输入，图片已保存进日报但未发送给 AI。'**
  String get homeAiNoticeImageUnsupported;

  /// No description provided for @homeAiNoticeGlobalSignFailed.
  ///
  /// In zh, this message translates to:
  /// **'三栏与日报已生成，但全局签 AI 更新失败，全局签内容未变更。'**
  String get homeAiNoticeGlobalSignFailed;

  /// No description provided for @homeGlobalSignFallbackDone.
  ///
  /// In zh, this message translates to:
  /// **'无法调用 AI，已在本地更新全局签，并将完成/取消内容写入当日日报。'**
  String get homeGlobalSignFallbackDone;

  /// No description provided for @homeGlobalSignFallbackUpdated.
  ///
  /// In zh, this message translates to:
  /// **'日报已更新，但全局签 AI 刷新失败，已在本地移除完成/取消项。'**
  String get homeGlobalSignFallbackUpdated;

  /// No description provided for @homeGlobalSignFallbackSaved.
  ///
  /// In zh, this message translates to:
  /// **'全局签 AI 刷新失败，已在本地保存修改。'**
  String get homeGlobalSignFallbackSaved;

  /// No description provided for @homeGlobalSignUnconfirmedChanges.
  ///
  /// In zh, this message translates to:
  /// **'有未确认的变更'**
  String get homeGlobalSignUnconfirmedChanges;

  /// No description provided for @homeGlobalSignConfirmHint.
  ///
  /// In zh, this message translates to:
  /// **'完成 / 取消 / 修改后请点击确认'**
  String get homeGlobalSignConfirmHint;

  /// No description provided for @homeGlobalSignTooltipUndoComplete.
  ///
  /// In zh, this message translates to:
  /// **'撤销完成'**
  String get homeGlobalSignTooltipUndoComplete;

  /// No description provided for @homeGlobalSignTooltipComplete.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get homeGlobalSignTooltipComplete;

  /// No description provided for @homeGlobalSignTooltipUndoCancel.
  ///
  /// In zh, this message translates to:
  /// **'撤销取消'**
  String get homeGlobalSignTooltipUndoCancel;

  /// No description provided for @homeGlobalSignTooltipCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get homeGlobalSignTooltipCancel;

  /// No description provided for @homeGlobalSignTooltipDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get homeGlobalSignTooltipDelete;

  /// No description provided for @homeGlobalSignDeleteConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除这条全局签？'**
  String get homeGlobalSignDeleteConfirmTitle;

  /// No description provided for @homeGlobalSignDeleteConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'删除后不会写入日报，也不会经过 AI 整理，且无法恢复。'**
  String get homeGlobalSignDeleteConfirmMessage;

  /// No description provided for @homeDesktopLevelTitle.
  ///
  /// In zh, this message translates to:
  /// **'Lv.{level} 实习生 ({percent}%)'**
  String homeDesktopLevelTitle(Object level, Object percent);

  /// No description provided for @homeActivityCountTimes.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次'**
  String homeActivityCountTimes(Object count);

  /// No description provided for @homeActivityCountDays.
  ///
  /// In zh, this message translates to:
  /// **'{count} 天'**
  String homeActivityCountDays(Object count);

  /// No description provided for @memoryChatHint.
  ///
  /// In zh, this message translates to:
  /// **'继续追问你的回忆...'**
  String get memoryChatHint;

  /// No description provided for @memoryEntryHint.
  ///
  /// In zh, this message translates to:
  /// **'问问你的回忆...'**
  String get memoryEntryHint;

  /// No description provided for @memoryEntryTitle.
  ///
  /// In zh, this message translates to:
  /// **'准备好了，随时开始'**
  String get memoryEntryTitle;

  /// No description provided for @memoryInputModeMindMapDescription.
  ///
  /// In zh, this message translates to:
  /// **'以思维导图呈现回答'**
  String get memoryInputModeMindMapDescription;

  /// No description provided for @memoryInputModeMindMapLabel.
  ///
  /// In zh, this message translates to:
  /// **'思维导图'**
  String get memoryInputModeMindMapLabel;

  /// No description provided for @memoryInputModeTooltip.
  ///
  /// In zh, this message translates to:
  /// **'输入模式'**
  String get memoryInputModeTooltip;

  /// No description provided for @memoryModelRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'模型请求失败。'**
  String get memoryModelRequestFailed;

  /// No description provided for @memoryMockAnswerEmpty.
  ///
  /// In zh, this message translates to:
  /// **'## AI 回答\n\n我还没有在日报、周报或月报中检索到和「{question}」直接相关的记录。你可以换一个更具体的关键词，例如项目名、模块名、问题现象或日期。'**
  String memoryMockAnswerEmpty(Object question);

  /// No description provided for @memoryMockAnswerSourceItem.
  ///
  /// In zh, this message translates to:
  /// **'- **{title}**：{snippet}'**
  String memoryMockAnswerSourceItem(Object snippet, Object title);

  /// No description provided for @memoryMockAnswerToolStep.
  ///
  /// In zh, this message translates to:
  /// **'- Thought：{thought}\n  Act：{toolLabel}（{query}）\n  Observation：{observation}'**
  String memoryMockAnswerToolStep(
    Object observation,
    Object query,
    Object thought,
    Object toolLabel,
  );

  /// No description provided for @memoryMockAnswerWithSources.
  ///
  /// In zh, this message translates to:
  /// **'## 使用的工具\n\n{toolList}\n\n## 找到的相关回忆\n\n{sourceList}\n\n---\n\n## AI 回答\n\n当前未配置可用的回忆书模型，所以先基于本地工具检索给出摘要。上面这些记录可能和「{question}」有关，你可以配置回忆书模型后获得更完整的解释、归纳和追问建议。'**
  String memoryMockAnswerWithSources(
    Object question,
    Object sourceList,
    Object toolList,
  );

  /// No description provided for @memoryNewConversationTooltip.
  ///
  /// In zh, this message translates to:
  /// **'开启新对话'**
  String get memoryNewConversationTooltip;

  /// No description provided for @memoryNoUsableAnswer.
  ///
  /// In zh, this message translates to:
  /// **'我没有拿到可用回答。'**
  String get memoryNoUsableAnswer;

  /// No description provided for @memoryPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'回忆书'**
  String get memoryPageTitle;

  /// No description provided for @memoryQuickPromptMonthReport.
  ///
  /// In zh, this message translates to:
  /// **'查看本月月报'**
  String get memoryQuickPromptMonthReport;

  /// No description provided for @memoryQuickPromptTodayDaily.
  ///
  /// In zh, this message translates to:
  /// **'查看今天日报'**
  String get memoryQuickPromptTodayDaily;

  /// No description provided for @memoryQuickPromptWeekDaily.
  ///
  /// In zh, this message translates to:
  /// **'查看本周日报'**
  String get memoryQuickPromptWeekDaily;

  /// No description provided for @memoryReasoningTitle.
  ///
  /// In zh, this message translates to:
  /// **'深度思考'**
  String get memoryReasoningTitle;

  /// No description provided for @memoryToolArgumentsLabel.
  ///
  /// In zh, this message translates to:
  /// **'传入参数'**
  String get memoryToolArgumentsLabel;

  /// No description provided for @memoryToolCallsLimitReached.
  ///
  /// In zh, this message translates to:
  /// **'工具调用轮次已达到上限。请把问题缩小到具体日期、项目名或关键词后再试。'**
  String get memoryToolCallsLimitReached;

  /// No description provided for @memoryToolLabelGetCurrentDate.
  ///
  /// In zh, this message translates to:
  /// **'获取当前日期'**
  String get memoryToolLabelGetCurrentDate;

  /// No description provided for @memoryToolLabelKeywordSearch.
  ///
  /// In zh, this message translates to:
  /// **'关键词搜索'**
  String get memoryToolLabelKeywordSearch;

  /// No description provided for @memoryToolLabelReadDailyNote.
  ///
  /// In zh, this message translates to:
  /// **'读取日报'**
  String get memoryToolLabelReadDailyNote;

  /// No description provided for @memoryToolLabelReadMonthReport.
  ///
  /// In zh, this message translates to:
  /// **'读取月报'**
  String get memoryToolLabelReadMonthReport;

  /// No description provided for @memoryToolLabelReadMonthWeeklyNotes.
  ///
  /// In zh, this message translates to:
  /// **'读取月内周报'**
  String get memoryToolLabelReadMonthWeeklyNotes;

  /// No description provided for @memoryToolLabelReadWeekDailyNotes.
  ///
  /// In zh, this message translates to:
  /// **'读取周内日报'**
  String get memoryToolLabelReadWeekDailyNotes;

  /// No description provided for @memoryToolLabelReadWeeklyNote.
  ///
  /// In zh, this message translates to:
  /// **'读取周报'**
  String get memoryToolLabelReadWeeklyNote;

  /// No description provided for @memoryToolLabelSearchDailyNotes.
  ///
  /// In zh, this message translates to:
  /// **'搜索日报关键词'**
  String get memoryToolLabelSearchDailyNotes;

  /// No description provided for @memoryToolLabelSearchMonthlyNotes.
  ///
  /// In zh, this message translates to:
  /// **'搜索月报关键词'**
  String get memoryToolLabelSearchMonthlyNotes;

  /// No description provided for @memoryToolLabelSearchWeeklyNotes.
  ///
  /// In zh, this message translates to:
  /// **'搜索周报关键词'**
  String get memoryToolLabelSearchWeeklyNotes;

  /// No description provided for @memoryToolNameLabel.
  ///
  /// In zh, this message translates to:
  /// **'工具名称'**
  String get memoryToolNameLabel;

  /// No description provided for @memoryToolNoResult.
  ///
  /// In zh, this message translates to:
  /// **'暂无返回结果'**
  String get memoryToolNoResult;

  /// No description provided for @memoryToolResultCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条结果'**
  String memoryToolResultCount(Object count);

  /// No description provided for @memoryToolResultLabel.
  ///
  /// In zh, this message translates to:
  /// **'返回结果'**
  String get memoryToolResultLabel;

  /// No description provided for @memoryToolResultNone.
  ///
  /// In zh, this message translates to:
  /// **'无结果'**
  String get memoryToolResultNone;

  /// No description provided for @memoryToolResultReturned.
  ///
  /// In zh, this message translates to:
  /// **'已返回'**
  String get memoryToolResultReturned;

  /// No description provided for @memoryWaitingIndicator.
  ///
  /// In zh, this message translates to:
  /// **'正在思考并调用工具...'**
  String get memoryWaitingIndicator;

  /// No description provided for @notesPreviewEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'预览区域会随着 Markdown 源码实时刷新'**
  String get notesPreviewEmptyHint;

  /// No description provided for @notesFimReady.
  ///
  /// In zh, this message translates to:
  /// **'AI 实时补全已就绪'**
  String get notesFimReady;

  /// No description provided for @notesSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get notesSaved;

  /// No description provided for @notesAutoSyncFailedMessage.
  ///
  /// In zh, this message translates to:
  /// **'自动同步失败：{message}'**
  String notesAutoSyncFailedMessage(Object message);

  /// No description provided for @notesAutoSyncFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'自动同步失败，请稍后重试。'**
  String get notesAutoSyncFailedRetry;

  /// No description provided for @notesFimPredicting.
  ///
  /// In zh, this message translates to:
  /// **'AI 编辑预测中'**
  String get notesFimPredicting;

  /// No description provided for @notesFimAcceptHint.
  ///
  /// In zh, this message translates to:
  /// **'Tab 全部 · Ctrl+L 单行 · Ctrl+K 单字'**
  String get notesFimAcceptHint;

  /// No description provided for @notesFimNotTriggered.
  ///
  /// In zh, this message translates to:
  /// **'FIM 未触发：{reason}'**
  String notesFimNotTriggered(Object reason);

  /// No description provided for @notesFimRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'FIM 请求失败：{error}'**
  String notesFimRequestFailed(Object error);

  /// No description provided for @notesFimNoPrediction.
  ///
  /// In zh, this message translates to:
  /// **'FIM 已请求，但没有返回可用预测'**
  String get notesFimNoPrediction;

  /// No description provided for @notesRegenerated.
  ///
  /// In zh, this message translates to:
  /// **'已重新生成'**
  String get notesRegenerated;

  /// No description provided for @notesRegenerateFailedMessage.
  ///
  /// In zh, this message translates to:
  /// **'重新生成失败：{message}'**
  String notesRegenerateFailedMessage(Object message);

  /// No description provided for @notesRegenerateFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'重新生成失败，请稍后重试。'**
  String get notesRegenerateFailedRetry;

  /// No description provided for @notesImageSelectionCanceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消选择图片'**
  String get notesImageSelectionCanceled;

  /// No description provided for @notesImageInserted.
  ///
  /// In zh, this message translates to:
  /// **'已插入图片'**
  String get notesImageInserted;

  /// No description provided for @notesImageFormatUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'图片格式不支持，请重新选择文件。'**
  String get notesImageFormatUnsupported;

  /// No description provided for @notesImageInsertFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法插入图片，请重新选择文件。'**
  String get notesImageInsertFailed;

  /// No description provided for @notesImagePasted.
  ///
  /// In zh, this message translates to:
  /// **'已粘贴图片'**
  String get notesImagePasted;

  /// No description provided for @notesClipboardImageFormatUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'图片格式不支持，请重新复制图片文件。'**
  String get notesClipboardImageFormatUnsupported;

  /// No description provided for @notesClipboardImagePasteFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法粘贴图片，请重新获取图片后重试。'**
  String get notesClipboardImagePasteFailed;

  /// No description provided for @notesClipboardTextReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取剪贴板文字。'**
  String get notesClipboardTextReadFailed;

  /// No description provided for @notesClipboardEmpty.
  ///
  /// In zh, this message translates to:
  /// **'剪贴板中没有可粘贴的内容。'**
  String get notesClipboardEmpty;

  /// No description provided for @notesSelectImage.
  ///
  /// In zh, this message translates to:
  /// **'选择图片'**
  String get notesSelectImage;

  /// No description provided for @notesNotebookTitle.
  ///
  /// In zh, this message translates to:
  /// **'笔记本'**
  String get notesNotebookTitle;

  /// No description provided for @notesSearchAllHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索全部{kindLabel}...'**
  String notesSearchAllHint(Object kindLabel);

  /// No description provided for @notesNoMatchingNotes.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的便签'**
  String get notesNoMatchingNotes;

  /// No description provided for @notesSearchMinChars.
  ///
  /// In zh, this message translates to:
  /// **'至少输入 2 个字符'**
  String get notesSearchMinChars;

  /// No description provided for @notesSearching.
  ///
  /// In zh, this message translates to:
  /// **'正在搜索...'**
  String get notesSearching;

  /// No description provided for @notesNoSearchResults.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配内容'**
  String get notesNoSearchResults;

  /// No description provided for @notesSwitchKindSemantics.
  ///
  /// In zh, this message translates to:
  /// **'切换日报/周报/月报'**
  String get notesSwitchKindSemantics;

  /// No description provided for @notesSwitchNoteType.
  ///
  /// In zh, this message translates to:
  /// **'切换笔记类型'**
  String get notesSwitchNoteType;

  /// No description provided for @notesKindDailyDescription.
  ///
  /// In zh, this message translates to:
  /// **'每日记录'**
  String get notesKindDailyDescription;

  /// No description provided for @notesKindWeeklyDescription.
  ///
  /// In zh, this message translates to:
  /// **'阶段整理'**
  String get notesKindWeeklyDescription;

  /// No description provided for @notesKindMonthlyDescription.
  ///
  /// In zh, this message translates to:
  /// **'月度沉淀'**
  String get notesKindMonthlyDescription;

  /// No description provided for @notesInsertImageTooltip.
  ///
  /// In zh, this message translates to:
  /// **'插入图片'**
  String get notesInsertImageTooltip;

  /// No description provided for @notesRegenerateTooltip.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get notesRegenerateTooltip;

  /// No description provided for @notesEditorHint.
  ///
  /// In zh, this message translates to:
  /// **'# 开始编辑 Markdown...'**
  String get notesEditorHint;

  /// No description provided for @notesWorkspaceModeEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get notesWorkspaceModeEdit;

  /// No description provided for @notesWorkspaceModeSplit.
  ///
  /// In zh, this message translates to:
  /// **'分栏'**
  String get notesWorkspaceModeSplit;

  /// No description provided for @notesWorkspaceModePreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get notesWorkspaceModePreview;

  /// No description provided for @settingsProvidersSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索供应商'**
  String get settingsProvidersSearchHint;

  /// No description provided for @settingsNoProviders.
  ///
  /// In zh, this message translates to:
  /// **'暂无供应商'**
  String get settingsNoProviders;

  /// No description provided for @settingsNoMatchingProviders.
  ///
  /// In zh, this message translates to:
  /// **'未找到匹配的供应商'**
  String get settingsNoMatchingProviders;

  /// No description provided for @settingsAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get settingsAdd;

  /// No description provided for @settingsProviderName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get settingsProviderName;

  /// No description provided for @settingsApiPath.
  ///
  /// In zh, this message translates to:
  /// **'API 路径'**
  String get settingsApiPath;

  /// No description provided for @settingsAddModelFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先添加至少一个模型。'**
  String get settingsAddModelFirst;

  /// No description provided for @settingsModelAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加 {modelName}'**
  String settingsModelAdded(Object modelName);

  /// No description provided for @settingsModelRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除模型'**
  String get settingsModelRemoved;

  /// No description provided for @settingsFetchModelsFailed.
  ///
  /// In zh, this message translates to:
  /// **'获取模型失败，请检查供应商配置。'**
  String get settingsFetchModelsFailed;

  /// No description provided for @settingsDeleteProvider.
  ///
  /// In zh, this message translates to:
  /// **'删除供应商'**
  String get settingsDeleteProvider;

  /// No description provided for @settingsDeleteProviderConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除该供应商吗？此操作不可撤销。'**
  String get settingsDeleteProviderConfirm;

  /// No description provided for @settingsTestingStream.
  ///
  /// In zh, this message translates to:
  /// **'流式测试中'**
  String get settingsTestingStream;

  /// No description provided for @settingsTesting.
  ///
  /// In zh, this message translates to:
  /// **'测试中'**
  String get settingsTesting;

  /// No description provided for @settingsConnectionTestFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接测试失败'**
  String get settingsConnectionTestFailed;

  /// No description provided for @settingsTestConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get settingsTestConnection;

  /// No description provided for @settingsUseStreaming.
  ///
  /// In zh, this message translates to:
  /// **'使用流式'**
  String get settingsUseStreaming;

  /// No description provided for @settingsTest.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get settingsTest;

  /// No description provided for @settingsConnectionSucceeded.
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get settingsConnectionSucceeded;

  /// No description provided for @settingsConnectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败'**
  String get settingsConnectionFailed;

  /// No description provided for @settingsSelectModel.
  ///
  /// In zh, this message translates to:
  /// **'选择模型'**
  String get settingsSelectModel;

  /// No description provided for @settingsTestSucceeded.
  ///
  /// In zh, this message translates to:
  /// **'测试成功'**
  String get settingsTestSucceeded;

  /// No description provided for @settingsSearchModelsOrProviders.
  ///
  /// In zh, this message translates to:
  /// **'搜索模型或服务商'**
  String get settingsSearchModelsOrProviders;

  /// No description provided for @settingsNoMatchingModels.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的模型'**
  String get settingsNoMatchingModels;

  /// No description provided for @settingsProviderModelsTitle.
  ///
  /// In zh, this message translates to:
  /// **'{providerName} 模型'**
  String settingsProviderModelsTitle(Object providerName);

  /// No description provided for @settingsSelectModelsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择要添加到当前提供商的模型'**
  String get settingsSelectModelsSubtitle;

  /// No description provided for @settingsRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get settingsRefresh;

  /// No description provided for @settingsSearchModels.
  ///
  /// In zh, this message translates to:
  /// **'搜索模型'**
  String get settingsSearchModels;

  /// No description provided for @settingsNoModelsFetched.
  ///
  /// In zh, this message translates to:
  /// **'没有获取到模型'**
  String get settingsNoModelsFetched;

  /// No description provided for @settingsFetchingModels.
  ///
  /// In zh, this message translates to:
  /// **'正在获取模型...'**
  String get settingsFetchingModels;

  /// No description provided for @settingsRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get settingsRetry;

  /// No description provided for @settingsOtherModels.
  ///
  /// In zh, this message translates to:
  /// **'其他模型'**
  String get settingsOtherModels;

  /// No description provided for @settingsModels.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get settingsModels;

  /// No description provided for @settingsFetching.
  ///
  /// In zh, this message translates to:
  /// **'获取中'**
  String get settingsFetching;

  /// No description provided for @settingsFetchModels.
  ///
  /// In zh, this message translates to:
  /// **'获取模型'**
  String get settingsFetchModels;

  /// No description provided for @settingsAddModel.
  ///
  /// In zh, this message translates to:
  /// **'添加模型'**
  String get settingsAddModel;

  /// No description provided for @settingsNoModels.
  ///
  /// In zh, this message translates to:
  /// **'暂无模型'**
  String get settingsNoModels;

  /// No description provided for @settingsAddModelViaButton.
  ///
  /// In zh, this message translates to:
  /// **'点击右上角添加'**
  String get settingsAddModelViaButton;

  /// No description provided for @settingsEditModel.
  ///
  /// In zh, this message translates to:
  /// **'编辑模型'**
  String get settingsEditModel;

  /// No description provided for @settingsDeleteModel.
  ///
  /// In zh, this message translates to:
  /// **'删除模型'**
  String get settingsDeleteModel;

  /// No description provided for @settingsAddProvider.
  ///
  /// In zh, this message translates to:
  /// **'添加供应商'**
  String get settingsAddProvider;

  /// No description provided for @settingsEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get settingsEnabled;

  /// No description provided for @settingsModelId.
  ///
  /// In zh, this message translates to:
  /// **'模型 ID'**
  String get settingsModelId;

  /// No description provided for @settingsModelName.
  ///
  /// In zh, this message translates to:
  /// **'模型名称'**
  String get settingsModelName;

  /// No description provided for @settingsEditModelSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'调整模型展示名称、输入类型与可用能力'**
  String get settingsEditModelSubtitle;

  /// No description provided for @settingsModelType.
  ///
  /// In zh, this message translates to:
  /// **'模型类型'**
  String get settingsModelType;

  /// No description provided for @settingsModelTypeChat.
  ///
  /// In zh, this message translates to:
  /// **'聊天'**
  String get settingsModelTypeChat;

  /// No description provided for @settingsModelTypeCompletion.
  ///
  /// In zh, this message translates to:
  /// **'补全'**
  String get settingsModelTypeCompletion;

  /// No description provided for @settingsInputMode.
  ///
  /// In zh, this message translates to:
  /// **'输入模式'**
  String get settingsInputMode;

  /// No description provided for @settingsInputModeText.
  ///
  /// In zh, this message translates to:
  /// **'文本'**
  String get settingsInputModeText;

  /// No description provided for @settingsInputModeImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get settingsInputModeImage;

  /// No description provided for @settingsCapability.
  ///
  /// In zh, this message translates to:
  /// **'能力'**
  String get settingsCapability;

  /// No description provided for @settingsCapabilityTools.
  ///
  /// In zh, this message translates to:
  /// **'工具'**
  String get settingsCapabilityTools;

  /// No description provided for @settingsCapabilityReasoning.
  ///
  /// In zh, this message translates to:
  /// **'推理'**
  String get settingsCapabilityReasoning;

  /// No description provided for @settingsCompletionProtocol.
  ///
  /// In zh, this message translates to:
  /// **'补全协议'**
  String get settingsCompletionProtocol;

  /// No description provided for @settingsCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get settingsCopied;

  /// No description provided for @settingsCopyModelId.
  ///
  /// In zh, this message translates to:
  /// **'复制模型 ID'**
  String get settingsCopyModelId;

  /// No description provided for @settingsConnectionSettings.
  ///
  /// In zh, this message translates to:
  /// **'连接设置'**
  String get settingsConnectionSettings;

  /// No description provided for @settingsEnableCloudSync.
  ///
  /// In zh, this message translates to:
  /// **'启用云同步'**
  String get settingsEnableCloudSync;

  /// No description provided for @settingsWebdavUrl.
  ///
  /// In zh, this message translates to:
  /// **'WebDAV 地址'**
  String get settingsWebdavUrl;

  /// No description provided for @settingsAccount.
  ///
  /// In zh, this message translates to:
  /// **'账号'**
  String get settingsAccount;

  /// No description provided for @settingsSyncStrategy.
  ///
  /// In zh, this message translates to:
  /// **'同步策略'**
  String get settingsSyncStrategy;

  /// No description provided for @settingsSyncOnStartup.
  ///
  /// In zh, this message translates to:
  /// **'应用启动时自动同步'**
  String get settingsSyncOnStartup;

  /// No description provided for @settingsRealTimeSync.
  ///
  /// In zh, this message translates to:
  /// **'实时同步'**
  String get settingsRealTimeSync;

  /// No description provided for @settingsLastFullSync.
  ///
  /// In zh, this message translates to:
  /// **'最近一次全量同步'**
  String get settingsLastFullSync;

  /// No description provided for @settingsDeleteCanceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消删除，未执行删除项'**
  String get settingsDeleteCanceled;

  /// No description provided for @settingsDeleteModifyConflictsSkipped.
  ///
  /// In zh, this message translates to:
  /// **'已跳过删除修改冲突，未处理冲突项'**
  String get settingsDeleteModifyConflictsSkipped;

  /// No description provided for @settingsSyncPendingItems.
  ///
  /// In zh, this message translates to:
  /// **'仍有待确认项，请重新同步。'**
  String get settingsSyncPendingItems;

  /// No description provided for @settingsUrlInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入完整 URL'**
  String get settingsUrlInvalid;

  /// No description provided for @settingsUrlSchemeUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'仅支持 http/https'**
  String get settingsUrlSchemeUnsupported;

  /// No description provided for @settingsNotSyncedYet.
  ///
  /// In zh, this message translates to:
  /// **'尚未同步'**
  String get settingsNotSyncedYet;

  /// No description provided for @settingsPasswordAppToken.
  ///
  /// In zh, this message translates to:
  /// **'密码/应用令牌'**
  String get settingsPasswordAppToken;

  /// No description provided for @settingsConfirmDeleteSync.
  ///
  /// In zh, this message translates to:
  /// **'确认删除同步'**
  String get settingsConfirmDeleteSync;

  /// No description provided for @settingsDeleteSyncDescription.
  ///
  /// In zh, this message translates to:
  /// **'检测到删除操作，确认后将同步删除对应文件。'**
  String get settingsDeleteSyncDescription;

  /// No description provided for @settingsWillDeleteLocal.
  ///
  /// In zh, this message translates to:
  /// **'将删除本地文件'**
  String get settingsWillDeleteLocal;

  /// No description provided for @settingsWillDeleteRemote.
  ///
  /// In zh, this message translates to:
  /// **'将删除远端文件'**
  String get settingsWillDeleteRemote;

  /// No description provided for @settingsConfirmDeleteAndSync.
  ///
  /// In zh, this message translates to:
  /// **'确认删除并同步'**
  String get settingsConfirmDeleteAndSync;

  /// No description provided for @settingsUnhandledItems.
  ///
  /// In zh, this message translates to:
  /// **'仍有未处理项'**
  String get settingsUnhandledItems;

  /// No description provided for @settingsUnhandledItemsMessage.
  ///
  /// In zh, this message translates to:
  /// **'仍有 {count} 个文件未选择处理方式，将自动视为“跳过此项”，是否继续？'**
  String settingsUnhandledItemsMessage(Object count);

  /// No description provided for @settingsBackToSelection.
  ///
  /// In zh, this message translates to:
  /// **'返回选择'**
  String get settingsBackToSelection;

  /// No description provided for @settingsContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get settingsContinue;

  /// No description provided for @settingsDeleteConflictDetected.
  ///
  /// In zh, this message translates to:
  /// **'检测到删除冲突'**
  String get settingsDeleteConflictDetected;

  /// No description provided for @settingsDeleteConflictDescription.
  ///
  /// In zh, this message translates to:
  /// **'以下文件在一端已删除，另一端已修改，请选择最终保留的结果。'**
  String get settingsDeleteConflictDescription;

  /// No description provided for @settingsLocalModified.
  ///
  /// In zh, this message translates to:
  /// **'本地：已修改'**
  String get settingsLocalModified;

  /// No description provided for @settingsLocalDeleted.
  ///
  /// In zh, this message translates to:
  /// **'本地：已删除'**
  String get settingsLocalDeleted;

  /// No description provided for @settingsRemoteDeleted.
  ///
  /// In zh, this message translates to:
  /// **'远端：已删除'**
  String get settingsRemoteDeleted;

  /// No description provided for @settingsRemoteModified.
  ///
  /// In zh, this message translates to:
  /// **'远端：已修改'**
  String get settingsRemoteModified;

  /// No description provided for @settingsKeepLocalVersion.
  ///
  /// In zh, this message translates to:
  /// **'保留本地版本'**
  String get settingsKeepLocalVersion;

  /// No description provided for @settingsKeepLocalVersionTooltip.
  ///
  /// In zh, this message translates to:
  /// **'上传本地文件到远端，恢复远端文件。'**
  String get settingsKeepLocalVersionTooltip;

  /// No description provided for @settingsKeepLocalDeletion.
  ///
  /// In zh, this message translates to:
  /// **'保留本地删除'**
  String get settingsKeepLocalDeletion;

  /// No description provided for @settingsKeepLocalDeletionTooltip.
  ///
  /// In zh, this message translates to:
  /// **'删除远端文件，与本地删除状态保持一致。'**
  String get settingsKeepLocalDeletionTooltip;

  /// No description provided for @settingsKeepRemoteDeletion.
  ///
  /// In zh, this message translates to:
  /// **'保留远端删除'**
  String get settingsKeepRemoteDeletion;

  /// No description provided for @settingsKeepRemoteDeletionTooltip.
  ///
  /// In zh, this message translates to:
  /// **'删除本地文件，保持远端已删除的状态。'**
  String get settingsKeepRemoteDeletionTooltip;

  /// No description provided for @settingsKeepRemoteVersion.
  ///
  /// In zh, this message translates to:
  /// **'保留远端版本'**
  String get settingsKeepRemoteVersion;

  /// No description provided for @settingsKeepRemoteVersionTooltip.
  ///
  /// In zh, this message translates to:
  /// **'下载远端文件，恢复本地文件。'**
  String get settingsKeepRemoteVersionTooltip;

  /// No description provided for @settingsSkip.
  ///
  /// In zh, this message translates to:
  /// **'跳过'**
  String get settingsSkip;

  /// No description provided for @settingsSkipTooltip.
  ///
  /// In zh, this message translates to:
  /// **'本次不同步该文件，下次同步时仍会提示处理。'**
  String get settingsSkipTooltip;

  /// No description provided for @settingsStatsTotalLabel.
  ///
  /// In zh, this message translates to:
  /// **'共'**
  String get settingsStatsTotalLabel;

  /// No description provided for @settingsStatsConflictCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个冲突'**
  String settingsStatsConflictCount(Object count);

  /// No description provided for @settingsStatsHandledLabel.
  ///
  /// In zh, this message translates to:
  /// **'已处理'**
  String get settingsStatsHandledLabel;

  /// No description provided for @settingsStatsHandledValue.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个'**
  String settingsStatsHandledValue(Object count);

  /// No description provided for @settingsStatsRemainingLabel.
  ///
  /// In zh, this message translates to:
  /// **'剩余'**
  String get settingsStatsRemainingLabel;

  /// No description provided for @settingsStatsRemainingValue.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个'**
  String settingsStatsRemainingValue(Object count);

  /// No description provided for @settingsSkipAll.
  ///
  /// In zh, this message translates to:
  /// **'全部跳过'**
  String get settingsSkipAll;

  /// No description provided for @settingsContinueBySelection.
  ///
  /// In zh, this message translates to:
  /// **'按选择继续'**
  String get settingsContinueBySelection;

  /// No description provided for @settingsSyncActions.
  ///
  /// In zh, this message translates to:
  /// **'同步操作'**
  String get settingsSyncActions;

  /// No description provided for @settingsSyncing.
  ///
  /// In zh, this message translates to:
  /// **'同步中'**
  String get settingsSyncing;

  /// No description provided for @settingsManualSync.
  ///
  /// In zh, this message translates to:
  /// **'手动同步'**
  String get settingsManualSync;

  /// No description provided for @settingsStatsAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get settingsStatsAll;

  /// No description provided for @settingsStatsRecent30.
  ///
  /// In zh, this message translates to:
  /// **'最近 30 天'**
  String get settingsStatsRecent30;

  /// No description provided for @settingsStatsRecent30Days.
  ///
  /// In zh, this message translates to:
  /// **'最近30天'**
  String get settingsStatsRecent30Days;

  /// No description provided for @settingsStatsLastMonth.
  ///
  /// In zh, this message translates to:
  /// **'上个月'**
  String get settingsStatsLastMonth;

  /// No description provided for @settingsStatsLastQuarter.
  ///
  /// In zh, this message translates to:
  /// **'上个季度'**
  String get settingsStatsLastQuarter;

  /// No description provided for @settingsStatsCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get settingsStatsCustom;

  /// No description provided for @settingsStatsDateRange.
  ///
  /// In zh, this message translates to:
  /// **'{start} 至 {end}'**
  String settingsStatsDateRange(Object end, Object start);

  /// No description provided for @settingsStatsYearlyHeatmap.
  ///
  /// In zh, this message translates to:
  /// **'年度热力图'**
  String get settingsStatsYearlyHeatmap;

  /// No description provided for @settingsStatsOverview.
  ///
  /// In zh, this message translates to:
  /// **'总览'**
  String get settingsStatsOverview;

  /// No description provided for @settingsStatsUsageTrend.
  ///
  /// In zh, this message translates to:
  /// **'用量趋势'**
  String get settingsStatsUsageTrend;

  /// No description provided for @settingsStatsSummaries.
  ///
  /// In zh, this message translates to:
  /// **'总结数'**
  String get settingsStatsSummaries;

  /// No description provided for @settingsStatsFimCompletions.
  ///
  /// In zh, this message translates to:
  /// **'编辑补全次数'**
  String get settingsStatsFimCompletions;

  /// No description provided for @settingsStatsTotalRecords.
  ///
  /// In zh, this message translates to:
  /// **'总记录数'**
  String get settingsStatsTotalRecords;

  /// No description provided for @settingsStatsDailyNotes.
  ///
  /// In zh, this message translates to:
  /// **'日报数'**
  String get settingsStatsDailyNotes;

  /// No description provided for @settingsStatsWeeklyNotes.
  ///
  /// In zh, this message translates to:
  /// **'周报数'**
  String get settingsStatsWeeklyNotes;

  /// No description provided for @settingsStatsMonthlyNotes.
  ///
  /// In zh, this message translates to:
  /// **'月报数'**
  String get settingsStatsMonthlyNotes;

  /// No description provided for @settingsStatsInputTokens.
  ///
  /// In zh, this message translates to:
  /// **'输入 Tokens'**
  String get settingsStatsInputTokens;

  /// No description provided for @settingsStatsOutputTokens.
  ///
  /// In zh, this message translates to:
  /// **'输出 Tokens'**
  String get settingsStatsOutputTokens;

  /// No description provided for @settingsStatsCachedTokens.
  ///
  /// In zh, this message translates to:
  /// **'缓存 Tokens'**
  String get settingsStatsCachedTokens;

  /// No description provided for @settingsStatsAppLaunches.
  ///
  /// In zh, this message translates to:
  /// **'应用启动次数'**
  String get settingsStatsAppLaunches;

  /// No description provided for @settingsStatsMonthLabel.
  ///
  /// In zh, this message translates to:
  /// **'{month}月'**
  String settingsStatsMonthLabel(Object month);

  /// No description provided for @settingsStatsWeekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'一'**
  String get settingsStatsWeekdayMon;

  /// No description provided for @settingsStatsWeekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'三'**
  String get settingsStatsWeekdayWed;

  /// No description provided for @settingsStatsWeekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'五'**
  String get settingsStatsWeekdayFri;

  /// No description provided for @settingsStatsNoUsageRecords.
  ///
  /// In zh, this message translates to:
  /// **'暂无模型调用记录'**
  String get settingsStatsNoUsageRecords;

  /// No description provided for @settingsStatsOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get settingsStatsOther;

  /// No description provided for @settingsStatsCustomRangeTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义时间段'**
  String get settingsStatsCustomRangeTitle;

  /// No description provided for @settingsStatsStart.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get settingsStatsStart;

  /// No description provided for @settingsStatsEnd.
  ///
  /// In zh, this message translates to:
  /// **'结束'**
  String get settingsStatsEnd;

  /// No description provided for @settingsStatsApply.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get settingsStatsApply;

  /// No description provided for @settingsStatsWeekdayTue.
  ///
  /// In zh, this message translates to:
  /// **'周二'**
  String get settingsStatsWeekdayTue;

  /// No description provided for @settingsStatsWeekdayThu.
  ///
  /// In zh, this message translates to:
  /// **'周四'**
  String get settingsStatsWeekdayThu;

  /// No description provided for @settingsStatsWeekdaySat.
  ///
  /// In zh, this message translates to:
  /// **'周六'**
  String get settingsStatsWeekdaySat;

  /// No description provided for @settingsStatsWeekdaySun.
  ///
  /// In zh, this message translates to:
  /// **'周日'**
  String get settingsStatsWeekdaySun;

  /// No description provided for @settingsScanFailed.
  ///
  /// In zh, this message translates to:
  /// **'扫描失败：{error}'**
  String settingsScanFailed(Object error);

  /// No description provided for @settingsCleanFailed.
  ///
  /// In zh, this message translates to:
  /// **'清理失败：{error}'**
  String settingsCleanFailed(Object error);

  /// No description provided for @settingsCleanPartialFailed.
  ///
  /// In zh, this message translates to:
  /// **'已清理 {deletedCount} 张，{failedCount} 张删除失败。'**
  String settingsCleanPartialFailed(Object deletedCount, Object failedCount);

  /// No description provided for @settingsCleanNoFiles.
  ///
  /// In zh, this message translates to:
  /// **'图片引用已发生变化，没有删除任何文件。'**
  String get settingsCleanNoFiles;

  /// No description provided for @settingsCleanSkipped.
  ///
  /// In zh, this message translates to:
  /// **'已清理 {deletedCount} 张图片，{skippedCount} 张因引用变化已保留。'**
  String settingsCleanSkipped(Object deletedCount, Object skippedCount);

  /// No description provided for @settingsCleanDone.
  ///
  /// In zh, this message translates to:
  /// **'已清理 {deletedCount} 张图片，释放 {freedSize}。'**
  String settingsCleanDone(Object deletedCount, Object freedSize);

  /// No description provided for @settingsCleaning.
  ///
  /// In zh, this message translates to:
  /// **'正在清理'**
  String get settingsCleaning;

  /// No description provided for @settingsScanning.
  ///
  /// In zh, this message translates to:
  /// **'正在扫描'**
  String get settingsScanning;

  /// No description provided for @settingsImageAttachments.
  ///
  /// In zh, this message translates to:
  /// **'图片附件'**
  String get settingsImageAttachments;

  /// No description provided for @settingsRescan.
  ///
  /// In zh, this message translates to:
  /// **'重新扫描'**
  String get settingsRescan;

  /// No description provided for @settingsCleanImages.
  ///
  /// In zh, this message translates to:
  /// **'清理图片'**
  String get settingsCleanImages;

  /// No description provided for @settingsNoStats.
  ///
  /// In zh, this message translates to:
  /// **'暂无统计信息'**
  String get settingsNoStats;

  /// No description provided for @settingsAllImages.
  ///
  /// In zh, this message translates to:
  /// **'全部图片'**
  String get settingsAllImages;

  /// No description provided for @settingsStillInUse.
  ///
  /// In zh, this message translates to:
  /// **'仍在使用'**
  String get settingsStillInUse;

  /// No description provided for @settingsCleanable.
  ///
  /// In zh, this message translates to:
  /// **'可以清理'**
  String get settingsCleanable;

  /// No description provided for @settingsUnusedCount.
  ///
  /// In zh, this message translates to:
  /// **'未使用 {count}'**
  String settingsUnusedCount(Object count);

  /// No description provided for @settingsSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get settingsSelectAll;

  /// No description provided for @settingsDeselectAll.
  ///
  /// In zh, this message translates to:
  /// **'取消全选'**
  String get settingsDeselectAll;

  /// No description provided for @settingsSelectedSummary.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} · {size}'**
  String settingsSelectedSummary(Object count, Object size);

  /// No description provided for @settingsConfirmDelete.
  ///
  /// In zh, this message translates to:
  /// **'确认删除'**
  String get settingsConfirmDelete;

  /// No description provided for @settingsPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get settingsPreview;

  /// No description provided for @settingsPreviewFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法预览这张图片'**
  String get settingsPreviewFailed;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsSectionPreferences.
  ///
  /// In zh, this message translates to:
  /// **'偏好设置'**
  String get settingsSectionPreferences;

  /// No description provided for @settingsSectionProviders.
  ///
  /// In zh, this message translates to:
  /// **'供应商'**
  String get settingsSectionProviders;

  /// No description provided for @settingsSectionModels.
  ///
  /// In zh, this message translates to:
  /// **'默认模型'**
  String get settingsSectionModels;

  /// No description provided for @settingsSectionHotkeys.
  ///
  /// In zh, this message translates to:
  /// **'快捷键'**
  String get settingsSectionHotkeys;

  /// No description provided for @settingsSectionCloudSync.
  ///
  /// In zh, this message translates to:
  /// **'云同步'**
  String get settingsSectionCloudSync;

  /// No description provided for @settingsSectionStorage.
  ///
  /// In zh, this message translates to:
  /// **'存储管理'**
  String get settingsSectionStorage;

  /// No description provided for @settingsSectionStats.
  ///
  /// In zh, this message translates to:
  /// **'统计'**
  String get settingsSectionStats;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsSectionAbout;

  /// No description provided for @settingsImageFileType.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get settingsImageFileType;

  /// No description provided for @settingsImageNotSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择'**
  String get settingsImageNotSelected;

  /// No description provided for @settingsImagePickFailed.
  ///
  /// In zh, this message translates to:
  /// **'选择图片失败: {error}'**
  String settingsImagePickFailed(Object error);

  /// No description provided for @settingsPersonalInfoTitle.
  ///
  /// In zh, this message translates to:
  /// **'个人信息'**
  String get settingsPersonalInfoTitle;

  /// No description provided for @settingsDailyWorkHours.
  ///
  /// In zh, this message translates to:
  /// **'每日工作时长'**
  String get settingsDailyWorkHours;

  /// No description provided for @settingsHoursSuffix.
  ///
  /// In zh, this message translates to:
  /// **'小时'**
  String get settingsHoursSuffix;

  /// No description provided for @settingsDailySalary.
  ///
  /// In zh, this message translates to:
  /// **'日薪'**
  String get settingsDailySalary;

  /// No description provided for @settingsIndustry.
  ///
  /// In zh, this message translates to:
  /// **'所在行业'**
  String get settingsIndustry;

  /// No description provided for @settingsFontDisplayTitle.
  ///
  /// In zh, this message translates to:
  /// **'字体与显示'**
  String get settingsFontDisplayTitle;

  /// No description provided for @settingsAppFont.
  ///
  /// In zh, this message translates to:
  /// **'应用字体'**
  String get settingsAppFont;

  /// No description provided for @settingsFontSize.
  ///
  /// In zh, this message translates to:
  /// **'字体大小'**
  String get settingsFontSize;

  /// No description provided for @settingsMarkdownHighlight.
  ///
  /// In zh, this message translates to:
  /// **'Markdown 语法高亮'**
  String get settingsMarkdownHighlight;

  /// No description provided for @settingsBehaviorTitle.
  ///
  /// In zh, this message translates to:
  /// **'行为与启动'**
  String get settingsBehaviorTitle;

  /// No description provided for @settingsAutoStart.
  ///
  /// In zh, this message translates to:
  /// **'开机自启动'**
  String get settingsAutoStart;

  /// No description provided for @settingsShowUpdates.
  ///
  /// In zh, this message translates to:
  /// **'显示更新'**
  String get settingsShowUpdates;

  /// No description provided for @settingsApiLog.
  ///
  /// In zh, this message translates to:
  /// **'记录 API 网络日志'**
  String get settingsApiLog;

  /// No description provided for @settingsWallpaperTitle.
  ///
  /// In zh, this message translates to:
  /// **'壁纸'**
  String get settingsWallpaperTitle;

  /// No description provided for @settingsWallpaperMode.
  ///
  /// In zh, this message translates to:
  /// **'模式'**
  String get settingsWallpaperMode;

  /// No description provided for @settingsWallpaperModeDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认背景'**
  String get settingsWallpaperModeDefault;

  /// No description provided for @settingsWallpaperModeImage.
  ///
  /// In zh, this message translates to:
  /// **'本地图片'**
  String get settingsWallpaperModeImage;

  /// No description provided for @settingsWallpaperModeSolid.
  ///
  /// In zh, this message translates to:
  /// **'纯色'**
  String get settingsWallpaperModeSolid;

  /// No description provided for @settingsSelectImage.
  ///
  /// In zh, this message translates to:
  /// **'选择图片'**
  String get settingsSelectImage;

  /// No description provided for @settingsWallpaperFill.
  ///
  /// In zh, this message translates to:
  /// **'填充'**
  String get settingsWallpaperFill;

  /// No description provided for @settingsWallpaperFillStretch.
  ///
  /// In zh, this message translates to:
  /// **'拉伸'**
  String get settingsWallpaperFillStretch;

  /// No description provided for @settingsWallpaperFillCover.
  ///
  /// In zh, this message translates to:
  /// **'覆盖'**
  String get settingsWallpaperFillCover;

  /// No description provided for @settingsWallpaperFillCenter.
  ///
  /// In zh, this message translates to:
  /// **'居中'**
  String get settingsWallpaperFillCenter;

  /// No description provided for @settingsBackgroundColor.
  ///
  /// In zh, this message translates to:
  /// **'背景颜色'**
  String get settingsBackgroundColor;

  /// No description provided for @settingsOpacity.
  ///
  /// In zh, this message translates to:
  /// **'不透明度'**
  String get settingsOpacity;

  /// No description provided for @settingsBlur.
  ///
  /// In zh, this message translates to:
  /// **'模糊度'**
  String get settingsBlur;

  /// No description provided for @settingsMaskOpacity.
  ///
  /// In zh, this message translates to:
  /// **'蒙版浓度'**
  String get settingsMaskOpacity;

  /// No description provided for @settingsTransparentControls.
  ///
  /// In zh, this message translates to:
  /// **'透明控件模式'**
  String get settingsTransparentControls;

  /// No description provided for @settingsControlOpacity.
  ///
  /// In zh, this message translates to:
  /// **'控件不透明度'**
  String get settingsControlOpacity;

  /// No description provided for @settingsShowBorders.
  ///
  /// In zh, this message translates to:
  /// **'保留卡片描边'**
  String get settingsShowBorders;

  /// No description provided for @settingsTextContrast.
  ///
  /// In zh, this message translates to:
  /// **'文字颜色加深'**
  String get settingsTextContrast;

  /// No description provided for @settingsTrayTitle.
  ///
  /// In zh, this message translates to:
  /// **'托盘'**
  String get settingsTrayTitle;

  /// No description provided for @settingsShowTrayIcon.
  ///
  /// In zh, this message translates to:
  /// **'显示托盘图标'**
  String get settingsShowTrayIcon;

  /// No description provided for @settingsCloseToTray.
  ///
  /// In zh, this message translates to:
  /// **'关闭时最小化到托盘'**
  String get settingsCloseToTray;

  /// No description provided for @settingsDataSaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'数据保存'**
  String get settingsDataSaveTitle;

  /// No description provided for @settingsComponentTitle.
  ///
  /// In zh, this message translates to:
  /// **'组件设置'**
  String get settingsComponentTitle;

  /// No description provided for @settingsShowDesktopWidget.
  ///
  /// In zh, this message translates to:
  /// **'显示桌面组件'**
  String get settingsShowDesktopWidget;

  /// No description provided for @settingsOrbMode.
  ///
  /// In zh, this message translates to:
  /// **'桌面组件圆球模式'**
  String get settingsOrbMode;

  /// No description provided for @settingsWidgetWallpaperTitle.
  ///
  /// In zh, this message translates to:
  /// **'组件壁纸'**
  String get settingsWidgetWallpaperTitle;

  /// No description provided for @settingsWidgetWallpaperModeDefaultWhite.
  ///
  /// In zh, this message translates to:
  /// **'默认白色'**
  String get settingsWidgetWallpaperModeDefaultWhite;

  /// No description provided for @settingsPromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get settingsPromptTitle;

  /// No description provided for @settingsHomeSections.
  ///
  /// In zh, this message translates to:
  /// **'首页栏目'**
  String get settingsHomeSections;

  /// No description provided for @settingsDailyMergePrompt.
  ///
  /// In zh, this message translates to:
  /// **'日报整理'**
  String get settingsDailyMergePrompt;

  /// No description provided for @settingsGlobalSignPrompt.
  ///
  /// In zh, this message translates to:
  /// **'全局签整理'**
  String get settingsGlobalSignPrompt;

  /// No description provided for @settingsEditDailyMergePromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑日报整理提示词'**
  String get settingsEditDailyMergePromptTitle;

  /// No description provided for @settingsDailyMergePromptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入日报整理 Prompt...'**
  String get settingsDailyMergePromptHint;

  /// No description provided for @settingsEditGlobalSignPromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑全局签提示词'**
  String get settingsEditGlobalSignPromptTitle;

  /// No description provided for @settingsGlobalSignPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入全局签整理 Prompt...'**
  String get settingsGlobalSignPromptHint;

  /// No description provided for @settingsVariableCurrentDate.
  ///
  /// In zh, this message translates to:
  /// **'当前日期'**
  String get settingsVariableCurrentDate;

  /// No description provided for @settingsVariableExistingDailyContent.
  ///
  /// In zh, this message translates to:
  /// **'已有日报内容'**
  String get settingsVariableExistingDailyContent;

  /// No description provided for @settingsVariableRawInput.
  ///
  /// In zh, this message translates to:
  /// **'新增随手记录'**
  String get settingsVariableRawInput;

  /// No description provided for @settingsVariableIndustry.
  ///
  /// In zh, this message translates to:
  /// **'用户所在行业'**
  String get settingsVariableIndustry;

  /// No description provided for @settingsVariableDailyContent.
  ///
  /// In zh, this message translates to:
  /// **'当日日报内容'**
  String get settingsVariableDailyContent;

  /// No description provided for @settingsVariableGlobalSignJson.
  ///
  /// In zh, this message translates to:
  /// **'当前全局签 JSON'**
  String get settingsVariableGlobalSignJson;

  /// No description provided for @settingsMemoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'回忆书检索'**
  String get settingsMemoryTitle;

  /// No description provided for @settingsMemorySearchLimit.
  ///
  /// In zh, this message translates to:
  /// **'回忆书单轮最大搜索次数'**
  String get settingsMemorySearchLimit;

  /// No description provided for @settingsTimesSuffix.
  ///
  /// In zh, this message translates to:
  /// **'次'**
  String get settingsTimesSuffix;

  /// No description provided for @settingsMemoryResultMaxChars.
  ///
  /// In zh, this message translates to:
  /// **'单条结果返回最大字符数'**
  String get settingsMemoryResultMaxChars;

  /// No description provided for @settingsCharsSuffix.
  ///
  /// In zh, this message translates to:
  /// **'字'**
  String get settingsCharsSuffix;

  /// No description provided for @settingsMemoryWeekDailyLimit.
  ///
  /// In zh, this message translates to:
  /// **'连续日报读取最大数量'**
  String get settingsMemoryWeekDailyLimit;

  /// No description provided for @settingsItemsSuffix.
  ///
  /// In zh, this message translates to:
  /// **'条'**
  String get settingsItemsSuffix;

  /// No description provided for @settingsMemoryKeywordSearchLimit.
  ///
  /// In zh, this message translates to:
  /// **'关键词搜索结果最大数量'**
  String get settingsMemoryKeywordSearchLimit;

  /// No description provided for @settingsMemoryKeywordBefore.
  ///
  /// In zh, this message translates to:
  /// **'命中关键词截取前最大字符数'**
  String get settingsMemoryKeywordBefore;

  /// No description provided for @settingsMemoryKeywordAfter.
  ///
  /// In zh, this message translates to:
  /// **'命中关键词截取后最大字符数'**
  String get settingsMemoryKeywordAfter;

  /// No description provided for @settingsConfigFileLabel.
  ///
  /// In zh, this message translates to:
  /// **'配置文件：{path}'**
  String settingsConfigFileLabel(Object path);

  /// No description provided for @settingsPlatformNotSupported.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂不支持'**
  String get settingsPlatformNotSupported;

  /// No description provided for @settingsDataMigrationComplete.
  ///
  /// In zh, this message translates to:
  /// **'数据迁移完成'**
  String get settingsDataMigrationComplete;

  /// No description provided for @settingsDataMigrationDetail.
  ///
  /// In zh, this message translates to:
  /// **'已成功切换至新的数据目录。\n确认数据正常后，可删除原目录以释放存储空间。'**
  String get settingsDataMigrationDetail;

  /// No description provided for @settingsSectionTitleHeader.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get settingsSectionTitleHeader;

  /// No description provided for @settingsAiInstructionHeader.
  ///
  /// In zh, this message translates to:
  /// **'AI 说明'**
  String get settingsAiInstructionHeader;

  /// No description provided for @settingsSectionTitleHint.
  ///
  /// In zh, this message translates to:
  /// **'栏目标题'**
  String get settingsSectionTitleHint;

  /// No description provided for @settingsSectionInstructionHint.
  ///
  /// In zh, this message translates to:
  /// **'描述分类规则'**
  String get settingsSectionInstructionHint;

  /// No description provided for @settingsFimReady.
  ///
  /// In zh, this message translates to:
  /// **'AI 实时补全已就绪'**
  String get settingsFimReady;

  /// No description provided for @settingsFimPredicting.
  ///
  /// In zh, this message translates to:
  /// **'AI 补全预测中'**
  String get settingsFimPredicting;

  /// No description provided for @settingsFimAcceptHint.
  ///
  /// In zh, this message translates to:
  /// **'Tab 全部 · Ctrl+L 单行 · Ctrl+K 单字'**
  String get settingsFimAcceptHint;

  /// No description provided for @settingsFimNotTriggered.
  ///
  /// In zh, this message translates to:
  /// **'FIM 未触发：{reason}'**
  String settingsFimNotTriggered(Object reason);

  /// No description provided for @settingsFimRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'FIM 请求失败：{error}'**
  String settingsFimRequestFailed(Object error);

  /// No description provided for @settingsFimNoPrediction.
  ///
  /// In zh, this message translates to:
  /// **'FIM 已请求，但没有返回可用预测'**
  String get settingsFimNoPrediction;

  /// No description provided for @settingsSelectThisFolder.
  ///
  /// In zh, this message translates to:
  /// **'选择此文件夹'**
  String get settingsSelectThisFolder;

  /// No description provided for @settingsSaveDirectory.
  ///
  /// In zh, this message translates to:
  /// **'保存目录'**
  String get settingsSaveDirectory;

  /// No description provided for @settingsDataDirectoryHint.
  ///
  /// In zh, this message translates to:
  /// **'当前保存目录'**
  String get settingsDataDirectoryHint;

  /// No description provided for @settingsSelectMigrateDirectory.
  ///
  /// In zh, this message translates to:
  /// **'选择并迁移目录'**
  String get settingsSelectMigrateDirectory;

  /// No description provided for @settingsRestoreDefaultDirectory.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认目录'**
  String get settingsRestoreDefaultDirectory;

  /// No description provided for @settingsSystemDefault.
  ///
  /// In zh, this message translates to:
  /// **'系统默认'**
  String get settingsSystemDefault;

  /// No description provided for @settingsResetFont.
  ///
  /// In zh, this message translates to:
  /// **'重置字体'**
  String get settingsResetFont;

  /// No description provided for @settingsSelectFont.
  ///
  /// In zh, this message translates to:
  /// **'选择字体'**
  String get settingsSelectFont;

  /// No description provided for @settingsSearchSystemFonts.
  ///
  /// In zh, this message translates to:
  /// **'搜索系统字体'**
  String get settingsSearchSystemFonts;

  /// No description provided for @settingsNoMatchingFonts.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的字体'**
  String get settingsNoMatchingFonts;

  /// No description provided for @settingsAppearanceMode.
  ///
  /// In zh, this message translates to:
  /// **'外观模式'**
  String get settingsAppearanceMode;

  /// No description provided for @settingsThemeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get settingsThemeDark;

  /// No description provided for @settingsProtocol.
  ///
  /// In zh, this message translates to:
  /// **'协议'**
  String get settingsProtocol;

  /// No description provided for @settingsDisabled.
  ///
  /// In zh, this message translates to:
  /// **'禁用'**
  String get settingsDisabled;

  /// No description provided for @settingsEmptyProviderDetails.
  ///
  /// In zh, this message translates to:
  /// **'添加供应商后在这里编辑配置'**
  String get settingsEmptyProviderDetails;

  /// No description provided for @settingsSelectColor.
  ///
  /// In zh, this message translates to:
  /// **'选择颜色'**
  String get settingsSelectColor;

  /// No description provided for @settingsModelIntelligent.
  ///
  /// In zh, this message translates to:
  /// **'智能生成模型'**
  String get settingsModelIntelligent;

  /// No description provided for @settingsModelIntelligentDesc.
  ///
  /// In zh, this message translates to:
  /// **'用于首页随手记录后的结构化整理和日报合并。'**
  String get settingsModelIntelligentDesc;

  /// No description provided for @settingsModelEditCompletion.
  ///
  /// In zh, this message translates to:
  /// **'编辑补全模型'**
  String get settingsModelEditCompletion;

  /// No description provided for @settingsModelEditCompletionDesc.
  ///
  /// In zh, this message translates to:
  /// **'用于便签页补全。模型类型包含补全时，默认按 completions FIM 调用。'**
  String get settingsModelEditCompletionDesc;

  /// No description provided for @settingsModelMemoryBook.
  ///
  /// In zh, this message translates to:
  /// **'回忆书模型'**
  String get settingsModelMemoryBook;

  /// No description provided for @settingsModelMemoryBookDesc.
  ///
  /// In zh, this message translates to:
  /// **'用于回忆书问答和历史记录检索回答。'**
  String get settingsModelMemoryBookDesc;

  /// No description provided for @settingsModelUnset.
  ///
  /// In zh, this message translates to:
  /// **'未'**
  String get settingsModelUnset;

  /// No description provided for @settingsModelSet.
  ///
  /// In zh, this message translates to:
  /// **'已'**
  String get settingsModelSet;

  /// No description provided for @settingsNoModelSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择模型'**
  String get settingsNoModelSelected;

  /// No description provided for @settingsSelectModelByProvider.
  ///
  /// In zh, this message translates to:
  /// **'按供应商选择默认模型'**
  String get settingsSelectModelByProvider;

  /// No description provided for @settingsNotSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择'**
  String get settingsNotSelected;

  /// No description provided for @settingsGlobalHotkeysTitle.
  ///
  /// In zh, this message translates to:
  /// **'全局快捷键'**
  String get settingsGlobalHotkeysTitle;

  /// No description provided for @settingsShowHidePage.
  ///
  /// In zh, this message translates to:
  /// **'显示/隐藏页面'**
  String get settingsShowHidePage;

  /// No description provided for @settingsReset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get settingsReset;

  /// No description provided for @settingsInputShortcutsTitle.
  ///
  /// In zh, this message translates to:
  /// **'输入快捷键'**
  String get settingsInputShortcutsTitle;

  /// No description provided for @settingsSendMessage.
  ///
  /// In zh, this message translates to:
  /// **'发送消息'**
  String get settingsSendMessage;

  /// No description provided for @settingsHotkeyNotSupported.
  ///
  /// In zh, this message translates to:
  /// **'暂不支持这个按键'**
  String get settingsHotkeyNotSupported;

  /// No description provided for @settingsHotkeyNeedModifiersMac.
  ///
  /// In zh, this message translates to:
  /// **'需包含 Cmd、Ctrl、Option 或 Shift'**
  String get settingsHotkeyNeedModifiersMac;

  /// No description provided for @settingsHotkeyNeedModifiersWin.
  ///
  /// In zh, this message translates to:
  /// **'需包含 Ctrl、Alt、Shift 或 Win'**
  String get settingsHotkeyNeedModifiersWin;

  /// No description provided for @settingsHotkeyPressHint.
  ///
  /// In zh, this message translates to:
  /// **'请按下快捷键'**
  String get settingsHotkeyPressHint;

  /// No description provided for @settingsHotkeyNotSet.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get settingsHotkeyNotSet;

  /// No description provided for @settingsAppTagline.
  ///
  /// In zh, this message translates to:
  /// **'AI 智能便签与日报生成工具'**
  String get settingsAppTagline;

  /// No description provided for @settingsCheckForUpdates.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get settingsCheckForUpdates;

  /// No description provided for @settingsWebsite.
  ///
  /// In zh, this message translates to:
  /// **'官网'**
  String get settingsWebsite;

  /// No description provided for @settingsLicense.
  ///
  /// In zh, this message translates to:
  /// **'许可证'**
  String get settingsLicense;

  /// No description provided for @settingsJoinQQGroup.
  ///
  /// In zh, this message translates to:
  /// **'加入QQ群'**
  String get settingsJoinQQGroup;

  /// No description provided for @settingsCheckingForUpdates.
  ///
  /// In zh, this message translates to:
  /// **'正在检查更新...'**
  String get settingsCheckingForUpdates;

  /// No description provided for @settingsUpdateContentUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法读取更新内容'**
  String get settingsUpdateContentUnavailable;

  /// No description provided for @settingsAlreadyUpToDate.
  ///
  /// In zh, this message translates to:
  /// **'当前已是最新版本'**
  String get settingsAlreadyUpToDate;

  /// No description provided for @settingsUpdateCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法检查更新，请稍后重试'**
  String get settingsUpdateCheckFailed;

  /// No description provided for @settingsVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get settingsVersion;

  /// No description provided for @settingsSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get settingsSystem;

  /// No description provided for @settingsUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get settingsUnknown;

  /// No description provided for @settingsSelectModelTitled.
  ///
  /// In zh, this message translates to:
  /// **'选择{title}'**
  String settingsSelectModelTitled(Object title);

  /// No description provided for @notesKindDaily.
  ///
  /// In zh, this message translates to:
  /// **'日报'**
  String get notesKindDaily;

  /// No description provided for @notesKindWeekly.
  ///
  /// In zh, this message translates to:
  /// **'周报'**
  String get notesKindWeekly;

  /// No description provided for @notesKindMonthly.
  ///
  /// In zh, this message translates to:
  /// **'月报'**
  String get notesKindMonthly;

  /// No description provided for @settingsMigrationErrorNested.
  ///
  /// In zh, this message translates to:
  /// **'保存目录不能选择当前数据目录的子目录。'**
  String get settingsMigrationErrorNested;

  /// No description provided for @settingsMigrationErrorIsFile.
  ///
  /// In zh, this message translates to:
  /// **'保存目录不能是一个文件。'**
  String get settingsMigrationErrorIsFile;

  /// No description provided for @settingsMigrationErrorMacAccess.
  ///
  /// In zh, this message translates to:
  /// **'无法保存 macOS 文件夹访问授权，请重新选择保存目录。'**
  String get settingsMigrationErrorMacAccess;

  /// No description provided for @settingsImageUnsupportedFormat.
  ///
  /// In zh, this message translates to:
  /// **'不支持的图片格式: {extension}'**
  String settingsImageUnsupportedFormat(Object extension);

  /// No description provided for @settingsImageSourceMissing.
  ///
  /// In zh, this message translates to:
  /// **'源图片不存在'**
  String get settingsImageSourceMissing;

  /// No description provided for @settingsProviderApiKeyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'供应商 API Key 为空。'**
  String get settingsProviderApiKeyEmpty;

  /// No description provided for @settingsWeeklyReportPrompt.
  ///
  /// In zh, this message translates to:
  /// **'周报整理'**
  String get settingsWeeklyReportPrompt;

  /// No description provided for @settingsEditWeeklyReportPromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑周报整理提示词'**
  String get settingsEditWeeklyReportPromptTitle;

  /// No description provided for @settingsWeeklyReportPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入周报整理 Prompt...'**
  String get settingsWeeklyReportPromptHint;

  /// No description provided for @settingsVariablePeriodLabel.
  ///
  /// In zh, this message translates to:
  /// **'周报周期'**
  String get settingsVariablePeriodLabel;

  /// No description provided for @settingsVariableSourceMarkdown.
  ///
  /// In zh, this message translates to:
  /// **'本周日报内容'**
  String get settingsVariableSourceMarkdown;

  /// No description provided for @memoryToolLabelResolveIsoWeek.
  ///
  /// In zh, this message translates to:
  /// **'获取周起止日期'**
  String get memoryToolLabelResolveIsoWeek;

  /// No description provided for @memoryToolLabelRunToolBatch.
  ///
  /// In zh, this message translates to:
  /// **'批量执行工具'**
  String get memoryToolLabelRunToolBatch;

  /// No description provided for @memoryToolLabelRunToolSequence.
  ///
  /// In zh, this message translates to:
  /// **'顺序执行工具'**
  String get memoryToolLabelRunToolSequence;

  /// No description provided for @memoryImageCountLimit.
  ///
  /// In zh, this message translates to:
  /// **'最多添加 4 张图片。'**
  String get memoryImageCountLimit;

  /// No description provided for @memoryImageInvalid.
  ///
  /// In zh, this message translates to:
  /// **'仅支持 5 MB 以内的 png、jpg、webp、gif 图片。'**
  String get memoryImageInvalid;

  /// No description provided for @memoryImageModelUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前回忆模型不支持图片输入。'**
  String get memoryImageModelUnsupported;

  /// No description provided for @memoryImageSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'图片保存失败，请重试。'**
  String get memoryImageSaveFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
