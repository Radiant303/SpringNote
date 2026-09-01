// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionSave => 'Save';

  @override
  String get actionClose => 'Close';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionRestore => 'Reset to default';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageZh => '中文';

  @override
  String get languageEn => 'English';

  @override
  String get coreStartupFailedTitle => 'SpringNote failed to start';

  @override
  String get coreAutoSyncIssueMessage =>
      'Auto sync hit a problem, please sync manually';

  @override
  String get coreSidebarHomeLabel => 'Home';

  @override
  String get coreSidebarNotesLabel => 'Notes';

  @override
  String get coreSidebarMemoryLabel => 'Memory';

  @override
  String get coreSidebarSettingsLabel => 'Settings';

  @override
  String get coreCodeCopy => 'Copy';

  @override
  String get coreCodeCopied => 'Copied';

  @override
  String get coreTreeGenerating => 'Generating…';

  @override
  String coreTreeInlineLimitHint(Object hidden, Object limit) {
    return 'Inline view shows up to $limit nodes; view the remaining $hidden in fullscreen';
  }

  @override
  String get coreTreeExitFullscreen => 'Exit fullscreen';

  @override
  String get coreTreeFullscreen => 'View fullscreen';

  @override
  String get coreTreeZoomIn => 'Zoom in';

  @override
  String get coreTreeZoomOut => 'Zoom out';

  @override
  String get coreTreeFitAll => 'Fit to view';

  @override
  String get coreUpdateDialogTitle => 'New version available';

  @override
  String get coreUpdateCurrentVersionLabel => 'Current version';

  @override
  String get coreUpdateLatestVersionLabel => 'Latest version';

  @override
  String get coreUpdateChangeTimeLabel => 'Updated';

  @override
  String get coreUpdateChangeTimeNotProvided => 'Not provided';

  @override
  String get coreUpdateChangelogTitle => 'What\'s new';

  @override
  String get coreUpdateChangelogEmpty => 'No update details yet.';

  @override
  String get coreUpdateChangelogLoadFailed => 'Failed to load update details.';

  @override
  String get coreUpdatePreparing => 'Preparing update...';

  @override
  String coreUpdateDownloading(Object received) {
    return 'Downloading installer $received';
  }

  @override
  String coreUpdateDownloadingProgress(Object received, Object total) {
    return 'Downloading installer $received / $total';
  }

  @override
  String get coreUpdateVerifying => 'Verifying installer...';

  @override
  String get coreUpdateExtracting => 'Extracting update...';

  @override
  String coreUpdateExtractingProgress(Object percent) {
    return 'Extracting update $percent%';
  }

  @override
  String get coreUpdateInstalling => 'Installing update...';

  @override
  String get coreUpdateLaunchingWindows =>
      'Launching installer; SpringNote will exit and restart...';

  @override
  String get coreUpdateLaunching =>
      'Restarting to replace with the new version...';

  @override
  String get coreUpdateButtonPreparing => 'Preparing';

  @override
  String get coreUpdateButtonInstallNow => 'Update now';

  @override
  String get coreUpdateLaunchFailed =>
      'Failed to launch the update. Please try again later.';

  @override
  String get coreUpdateErrorUnsupportedPlatform =>
      'Automatic updates are not supported on this platform.';

  @override
  String get coreUpdateErrorUpdaterMissing =>
      'Update helper is missing. Please download the latest installer and update manually.';

  @override
  String coreUpdateErrorDownloadFailed(Object status) {
    return 'Failed to download the installer ($status)';
  }

  @override
  String get coreUpdateErrorDownloadTimeout =>
      'Update download timed out. Please try again later.';

  @override
  String get coreUpdateErrorNetworkUnavailable =>
      'Network unavailable. Please check your connection and try again.';

  @override
  String get coreUpdateErrorDownloadFailedRetry =>
      'Failed to download the installer. Please try again later.';

  @override
  String get coreUpdateErrorChecksumFailed =>
      'Installer verification failed. Please try again later.';

  @override
  String get coreUpdateErrorChecksumUnreadable =>
      'Could not read installer verification info.';

  @override
  String get coreUpdateErrorChecksumMissing =>
      'Installer verification info not found.';

  @override
  String get coreUpdateErrorMacFailed =>
      'macOS update failed. Please try again later.';

  @override
  String get coreUpdateErrorMacNotFound => 'No installable macOS update found.';

  @override
  String get coreUpdateErrorMacDismissed =>
      'The macOS update flow ended. Please try again later.';

  @override
  String get coreUpdateErrorMacInterrupted =>
      'The macOS update flow was interrupted. Please try again later.';

  @override
  String get coreUpdateErrorMacLaunchFailed =>
      'Failed to start the macOS update. Please try again later.';

  @override
  String get homePageTitle => 'Home';

  @override
  String get homeEarningsTotalPrefix => 'Total earnings ';

  @override
  String get homeActivityRecent => 'Recently active';

  @override
  String get homeActivityWeeklySummary => 'This week';

  @override
  String get homeActivityStreak => 'Streak';

  @override
  String get homeActivityLastSync => 'Last sync';

  @override
  String get homeActivityJustNow => 'Just now';

  @override
  String get homeInputHint =>
      'Write your thoughts; AI will organize them into structured content...';

  @override
  String get homeUploadImageTooltip => 'Upload image';

  @override
  String get homeAddFileTooltip => 'Add file';

  @override
  String get homeMentionTooltip => 'Mention';

  @override
  String homeCharacterCount(Object count) {
    return '$count chars';
  }

  @override
  String get homeSmartGenerate => 'Generate';

  @override
  String get homeGenerating => 'Organizing';

  @override
  String homeImageChipLabel(Object name) {
    return 'Image · $name';
  }

  @override
  String get homeAttachmentImageLabel => 'Image';

  @override
  String get homeAttachmentFileLabel => 'File';

  @override
  String homeAttachmentChipLabel(Object name, Object type) {
    return '$type · $name';
  }

  @override
  String get homeEmptyHint => 'No content yet';

  @override
  String homeSavedPath(Object path) {
    return 'Saved to daily note: $path';
  }

  @override
  String homeUpdateAvailable(Object version) {
    return 'New version $version available, tap to view details';
  }

  @override
  String get homeUpdateCheckFailed => 'Update check failed';

  @override
  String get homeGlobalSign => 'Global sign';

  @override
  String get homeClipboardImageError => 'Unable to read clipboard image.';

  @override
  String get homeClipboardTextError => 'Unable to read clipboard text.';

  @override
  String get homeAddImageError => 'Unable to add image, please reselect.';

  @override
  String get homeAddAttachmentError =>
      'Unable to add attachment, please reselect.';

  @override
  String homeImageOversized(Object maxSize, Object names) {
    return 'Single image must not exceed $maxSize: $names.';
  }

  @override
  String homeImageLimitExceeded(Object count, Object max) {
    return 'Up to $max images allowed; $count skipped.';
  }

  @override
  String homeImageUnsupportedForAi(Object names) {
    return 'These images will be saved but not sent to AI: $names.';
  }

  @override
  String get homeNoImageToAdd => 'No images to add.';

  @override
  String get homePickImageButton => 'Select images';

  @override
  String get homePickFileButton => 'Select files';

  @override
  String get homeImageNamesSeparator => ', ';

  @override
  String homeImageNamesRemaining(Object count, Object names) {
    return '$names and $count more';
  }

  @override
  String get homeAiNoticeNoModel =>
      'No usable model configured or AI unavailable; used local fallback.';

  @override
  String get homeAiNoticeImageUnsupported =>
      'Current model doesn\'t support image input; images saved but not sent to AI.';

  @override
  String get homeAiNoticeGlobalSignFailed =>
      'Note generated, but global sign AI update failed; content unchanged.';

  @override
  String get homeGlobalSignFallbackDone =>
      'AI unavailable; global sign updated locally and changes written to daily note.';

  @override
  String get homeGlobalSignFallbackUpdated =>
      'Daily note updated, but global sign AI refresh failed; completed/cancelled items removed.';

  @override
  String get homeGlobalSignFallbackSaved =>
      'Global sign AI refresh failed; changes saved locally.';

  @override
  String get homeGlobalSignUnconfirmedChanges => 'Unconfirmed changes';

  @override
  String get homeGlobalSignConfirmHint =>
      'Click confirm after done / cancel / edit';

  @override
  String get homeGlobalSignTooltipUndoComplete => 'Undo complete';

  @override
  String get homeGlobalSignTooltipComplete => 'Complete';

  @override
  String get homeGlobalSignTooltipUndoCancel => 'Undo cancel';

  @override
  String get homeGlobalSignTooltipCancel => 'Cancel';

  @override
  String get homeGlobalSignTooltipDelete => 'Delete';

  @override
  String get homeGlobalSignDeleteConfirmTitle => 'Delete this global sign?';

  @override
  String get homeGlobalSignDeleteConfirmMessage =>
      'It won\'t be written to the daily note, won\'t be organized by AI, and can\'t be restored.';

  @override
  String homeDesktopLevelTitle(Object level, Object percent) {
    return 'Lv.$level Intern ($percent%)';
  }

  @override
  String homeActivityCountTimes(Object count) {
    return '$count times';
  }

  @override
  String homeActivityCountDays(Object count) {
    return '$count days';
  }

  @override
  String get memoryChatHint => 'Continue asking your memory...';

  @override
  String get memoryEntryHint => 'Ask your memory...';

  @override
  String get memoryEntryTitle => 'Ready when you are';

  @override
  String get memoryInputModeMindMapDescription =>
      'Present the answer as a mind map';

  @override
  String get memoryInputModeMindMapLabel => 'Mind map';

  @override
  String get memoryInputModeTooltip => 'Input modes';

  @override
  String get memoryModelRequestFailed => 'Model request failed.';

  @override
  String memoryMockAnswerEmpty(Object question) {
    return '## AI Answer\n\nI haven\'t found records directly related to 「$question」 in daily, weekly, or monthly notes. Try a more specific keyword, such as a project name, module name, issue, or date.';
  }

  @override
  String memoryMockAnswerSourceItem(Object snippet, Object title) {
    return '- **$title**: $snippet';
  }

  @override
  String memoryMockAnswerToolStep(
    Object observation,
    Object query,
    Object thought,
    Object toolLabel,
  ) {
    return '- Thought: $thought\n  Act: $toolLabel ($query)\n  Observation: $observation';
  }

  @override
  String memoryMockAnswerWithSources(
    Object question,
    Object sourceList,
    Object toolList,
  ) {
    return '## Tools Used\n\n$toolList\n\n## Related Memories Found\n\n$sourceList\n\n---\n\n## AI Answer\n\nNo memoir model is configured, so this summary is based on local tool retrieval. These records may relate to 「$question」. Configure a memoir model for fuller explanations, synthesis, and follow-up suggestions.';
  }

  @override
  String get memoryNewConversationTooltip => 'Start new conversation';

  @override
  String get memoryNoUsableAnswer => 'I didn\'t get a usable answer.';

  @override
  String get memoryPageTitle => 'Memoir';

  @override
  String get memoryQuickPromptMonthReport => 'View this month\'s report';

  @override
  String get memoryQuickPromptTodayDaily => 'View today\'s daily note';

  @override
  String get memoryQuickPromptWeekDaily => 'View this week\'s daily notes';

  @override
  String get memoryReasoningTitle => 'Deep reasoning';

  @override
  String get memoryToolArgumentsLabel => 'Arguments';

  @override
  String get memoryToolCallsLimitReached =>
      'Tool call rounds reached the limit. Try narrowing your question to a specific date, project name, or keyword.';

  @override
  String get memoryToolLabelGetCurrentDate => 'Get current date';

  @override
  String get memoryToolLabelKeywordSearch => 'Keyword search';

  @override
  String get memoryToolLabelReadDailyNote => 'Read daily note';

  @override
  String get memoryToolLabelReadMonthReport => 'Read monthly report';

  @override
  String get memoryToolLabelReadMonthWeeklyNotes =>
      'Read month\'s weekly notes';

  @override
  String get memoryToolLabelReadWeekDailyNotes => 'Read week\'s daily notes';

  @override
  String get memoryToolLabelReadWeeklyNote => 'Read weekly note';

  @override
  String get memoryToolLabelSearchDailyNotes => 'Search daily notes';

  @override
  String get memoryToolLabelSearchMonthlyNotes => 'Search monthly notes';

  @override
  String get memoryToolLabelSearchWeeklyNotes => 'Search weekly notes';

  @override
  String get memoryToolNameLabel => 'Tool name';

  @override
  String get memoryToolNoResult => 'No result yet';

  @override
  String memoryToolResultCount(Object count) {
    return '$count results';
  }

  @override
  String get memoryToolResultLabel => 'Result';

  @override
  String get memoryToolResultNone => 'No results';

  @override
  String get memoryToolResultReturned => 'Returned';

  @override
  String get memoryWaitingIndicator => 'Thinking and calling tools...';

  @override
  String get notesPreviewEmptyHint =>
      'Preview updates live as you edit Markdown';

  @override
  String get notesFimReady => 'AI real-time completion ready';

  @override
  String get notesSaved => 'Saved';

  @override
  String notesAutoSyncFailedMessage(Object message) {
    return 'Auto-sync failed: $message';
  }

  @override
  String get notesAutoSyncFailedRetry =>
      'Auto-sync failed, please try again later.';

  @override
  String get notesFimPredicting => 'AI editing prediction in progress';

  @override
  String get notesFimAcceptHint => 'Tab all · Ctrl+L line · Ctrl+K character';

  @override
  String notesFimNotTriggered(Object reason) {
    return 'FIM not triggered: $reason';
  }

  @override
  String notesFimRequestFailed(Object error) {
    return 'FIM request failed: $error';
  }

  @override
  String get notesFimNoPrediction =>
      'FIM requested, but no prediction available';

  @override
  String get notesRegenerated => 'Regenerated';

  @override
  String notesRegenerateFailedMessage(Object message) {
    return 'Regenerate failed: $message';
  }

  @override
  String get notesRegenerateFailedRetry =>
      'Regenerate failed, please try again later.';

  @override
  String get notesImageSelectionCanceled => 'Image selection canceled';

  @override
  String get notesImageInserted => 'Image inserted';

  @override
  String get notesImageFormatUnsupported =>
      'Unsupported image format, please select another file.';

  @override
  String get notesImageInsertFailed =>
      'Could not insert image, please select another file.';

  @override
  String get notesImagePasted => 'Image pasted';

  @override
  String get notesClipboardImageFormatUnsupported =>
      'Unsupported image format, please copy another image file.';

  @override
  String get notesClipboardImagePasteFailed =>
      'Could not paste image, please copy the image again.';

  @override
  String get notesClipboardTextReadFailed => 'Could not read clipboard text.';

  @override
  String get notesClipboardEmpty => 'Clipboard has nothing to paste.';

  @override
  String get notesSelectImage => 'Select image';

  @override
  String get notesNotebookTitle => 'Notebook';

  @override
  String notesSearchAllHint(Object kindLabel) {
    return 'Search all $kindLabel...';
  }

  @override
  String get notesNoMatchingNotes => 'No matching notes';

  @override
  String get notesSearchMinChars => 'Enter at least 2 characters';

  @override
  String get notesSearching => 'Searching...';

  @override
  String get notesNoSearchResults => 'No matches';

  @override
  String get notesSwitchKindSemantics => 'Switch daily/weekly/monthly report';

  @override
  String get notesSwitchNoteType => 'Switch note type';

  @override
  String get notesKindDailyDescription => 'Daily record';

  @override
  String get notesKindWeeklyDescription => 'Weekly summary';

  @override
  String get notesKindMonthlyDescription => 'Monthly review';

  @override
  String get notesInsertImageTooltip => 'Insert image';

  @override
  String get notesRegenerateTooltip => 'Regenerate';

  @override
  String get notesEditorHint => '# Start editing Markdown...';

  @override
  String get notesWorkspaceModeEdit => 'Edit';

  @override
  String get notesWorkspaceModeSplit => 'Split';

  @override
  String get notesWorkspaceModePreview => 'Preview';

  @override
  String get settingsProvidersSearchHint => 'Search providers';

  @override
  String get settingsNoProviders => 'No providers yet';

  @override
  String get settingsNoMatchingProviders => 'No matching providers';

  @override
  String get settingsAdd => 'Add';

  @override
  String get settingsProviderName => 'Name';

  @override
  String get settingsApiPath => 'API path';

  @override
  String get settingsAddModelFirst => 'Please add at least one model first.';

  @override
  String settingsModelAdded(Object modelName) {
    return 'Added $modelName';
  }

  @override
  String get settingsModelRemoved => 'Model removed';

  @override
  String get settingsFetchModelsFailed =>
      'Failed to fetch models. Please check the provider configuration.';

  @override
  String get settingsDeleteProvider => 'Delete provider';

  @override
  String get settingsDeleteProviderConfirm =>
      'Delete this provider? This action cannot be undone.';

  @override
  String get settingsTestingStream => 'Streaming test in progress';

  @override
  String get settingsTesting => 'Testing';

  @override
  String get settingsConnectionTestFailed => 'Connection test failed';

  @override
  String get settingsTestConnection => 'Test connection';

  @override
  String get settingsUseStreaming => 'Use streaming';

  @override
  String get settingsTest => 'Test';

  @override
  String get settingsConnectionSucceeded => 'Connection succeeded';

  @override
  String get settingsConnectionFailed => 'Connection failed';

  @override
  String get settingsSelectModel => 'Select model';

  @override
  String get settingsTestSucceeded => 'Test succeeded';

  @override
  String get settingsSearchModelsOrProviders => 'Search models or providers';

  @override
  String get settingsNoMatchingModels => 'No matching models';

  @override
  String settingsProviderModelsTitle(Object providerName) {
    return '$providerName models';
  }

  @override
  String get settingsSelectModelsSubtitle =>
      'Select models to add to the current provider';

  @override
  String get settingsRefresh => 'Refresh';

  @override
  String get settingsSearchModels => 'Search models';

  @override
  String get settingsNoModelsFetched => 'No models fetched';

  @override
  String get settingsFetchingModels => 'Fetching models...';

  @override
  String get settingsRetry => 'Retry';

  @override
  String get settingsOtherModels => 'Other models';

  @override
  String get settingsModels => 'Models';

  @override
  String get settingsFetching => 'Fetching';

  @override
  String get settingsFetchModels => 'Fetch models';

  @override
  String get settingsAddModel => 'Add model';

  @override
  String get settingsNoModels => 'No models';

  @override
  String get settingsAddModelViaButton =>
      'Click the button in the top-right corner to add';

  @override
  String get settingsEditModel => 'Edit model';

  @override
  String get settingsDeleteModel => 'Delete model';

  @override
  String get settingsAddProvider => 'Add provider';

  @override
  String get settingsEnabled => 'Enabled';

  @override
  String get settingsModelId => 'Model ID';

  @override
  String get settingsModelName => 'Model name';

  @override
  String get settingsEditModelSubtitle =>
      'Adjust the model display name, input types, and capabilities';

  @override
  String get settingsModelType => 'Model type';

  @override
  String get settingsModelTypeChat => 'Chat';

  @override
  String get settingsModelTypeCompletion => 'Completion';

  @override
  String get settingsInputMode => 'Input mode';

  @override
  String get settingsInputModeText => 'Text';

  @override
  String get settingsInputModeImage => 'Image';

  @override
  String get settingsCapability => 'Capabilities';

  @override
  String get settingsCapabilityTools => 'Tools';

  @override
  String get settingsCapabilityReasoning => 'Reasoning';

  @override
  String get settingsCompletionProtocol => 'Completion protocol';

  @override
  String get settingsCopied => 'Copied';

  @override
  String get settingsCopyModelId => 'Copy model ID';

  @override
  String get settingsConnectionSettings => 'Connection settings';

  @override
  String get settingsEnableCloudSync => 'Enable cloud sync';

  @override
  String get settingsWebdavUrl => 'WebDAV URL';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsSyncStrategy => 'Sync strategy';

  @override
  String get settingsSyncOnStartup => 'Auto-sync on app startup';

  @override
  String get settingsRealTimeSync => 'Real-time sync';

  @override
  String get settingsLastFullSync => 'Last full sync';

  @override
  String get settingsDeleteCanceled => 'Delete canceled; nothing was deleted';

  @override
  String get settingsDeleteModifyConflictsSkipped =>
      'Delete-modify conflicts skipped; no conflicts were processed';

  @override
  String get settingsSyncPendingItems =>
      'Some items still need confirmation. Please sync again.';

  @override
  String get settingsUrlInvalid => 'Please enter a complete URL';

  @override
  String get settingsUrlSchemeUnsupported => 'Only http/https are supported';

  @override
  String get settingsNotSyncedYet => 'Not synced yet';

  @override
  String get settingsPasswordAppToken => 'Password/App token';

  @override
  String get settingsConfirmDeleteSync => 'Confirm sync deletions';

  @override
  String get settingsDeleteSyncDescription =>
      'Deletions detected. Confirming will delete the corresponding files.';

  @override
  String get settingsWillDeleteLocal => 'Local files to delete';

  @override
  String get settingsWillDeleteRemote => 'Remote files to delete';

  @override
  String get settingsConfirmDeleteAndSync => 'Confirm and sync deletions';

  @override
  String get settingsUnhandledItems => 'Unhandled items remain';

  @override
  String settingsUnhandledItemsMessage(Object count) {
    return 'You still have $count files without a resolution; they will be treated as \"Skip\". Continue?';
  }

  @override
  String get settingsBackToSelection => 'Back to selection';

  @override
  String get settingsContinue => 'Continue';

  @override
  String get settingsDeleteConflictDetected => 'Delete conflict detected';

  @override
  String get settingsDeleteConflictDescription =>
      'The following files were deleted on one side and modified on the other. Choose which result to keep.';

  @override
  String get settingsLocalModified => 'Local: modified';

  @override
  String get settingsLocalDeleted => 'Local: deleted';

  @override
  String get settingsRemoteDeleted => 'Remote: deleted';

  @override
  String get settingsRemoteModified => 'Remote: modified';

  @override
  String get settingsKeepLocalVersion => 'Keep local version';

  @override
  String get settingsKeepLocalVersionTooltip =>
      'Upload the local file to the remote to restore it.';

  @override
  String get settingsKeepLocalDeletion => 'Keep local deletion';

  @override
  String get settingsKeepLocalDeletionTooltip =>
      'Delete the remote file to match the local deletion.';

  @override
  String get settingsKeepRemoteDeletion => 'Keep remote deletion';

  @override
  String get settingsKeepRemoteDeletionTooltip =>
      'Delete the local file to keep the remote deleted.';

  @override
  String get settingsKeepRemoteVersion => 'Keep remote version';

  @override
  String get settingsKeepRemoteVersionTooltip =>
      'Download the remote file to restore the local file.';

  @override
  String get settingsSkip => 'Skip';

  @override
  String get settingsSkipTooltip =>
      'This file will not sync this time; you will be prompted again on the next sync.';

  @override
  String get settingsStatsTotalLabel => 'Total';

  @override
  String settingsStatsConflictCount(Object count) {
    return '$count conflicts';
  }

  @override
  String get settingsStatsHandledLabel => 'Handled';

  @override
  String settingsStatsHandledValue(Object count) {
    return '$count';
  }

  @override
  String get settingsStatsRemainingLabel => 'Remaining';

  @override
  String settingsStatsRemainingValue(Object count) {
    return '$count';
  }

  @override
  String get settingsSkipAll => 'Skip all';

  @override
  String get settingsContinueBySelection => 'Continue with selection';

  @override
  String get settingsSyncActions => 'Sync actions';

  @override
  String get settingsSyncing => 'Syncing';

  @override
  String get settingsManualSync => 'Manual sync';

  @override
  String get settingsStatsAll => 'All';

  @override
  String get settingsStatsRecent30 => 'Last 30 days';

  @override
  String get settingsStatsRecent30Days => 'Last 30 days';

  @override
  String get settingsStatsLastMonth => 'Last month';

  @override
  String get settingsStatsLastQuarter => 'Last quarter';

  @override
  String get settingsStatsCustom => 'Custom';

  @override
  String settingsStatsDateRange(Object end, Object start) {
    return '$start to $end';
  }

  @override
  String get settingsStatsYearlyHeatmap => 'Yearly heatmap';

  @override
  String get settingsStatsOverview => 'Overview';

  @override
  String get settingsStatsUsageTrend => 'Usage trend';

  @override
  String get settingsStatsSummaries => 'Summaries';

  @override
  String get settingsStatsFimCompletions => 'FIM completions';

  @override
  String get settingsStatsTotalRecords => 'Total records';

  @override
  String get settingsStatsDailyNotes => 'Daily notes';

  @override
  String get settingsStatsWeeklyNotes => 'Weekly notes';

  @override
  String get settingsStatsMonthlyNotes => 'Monthly notes';

  @override
  String get settingsStatsInputTokens => 'Input tokens';

  @override
  String get settingsStatsOutputTokens => 'Output tokens';

  @override
  String get settingsStatsCachedTokens => 'Cached tokens';

  @override
  String get settingsStatsAppLaunches => 'App launches';

  @override
  String settingsStatsMonthLabel(Object month) {
    return '$month';
  }

  @override
  String get settingsStatsWeekdayMon => 'Mon';

  @override
  String get settingsStatsWeekdayWed => 'Wed';

  @override
  String get settingsStatsWeekdayFri => 'Fri';

  @override
  String get settingsStatsNoUsageRecords => 'No model usage records';

  @override
  String get settingsStatsOther => 'Other';

  @override
  String get settingsStatsCustomRangeTitle => 'Custom date range';

  @override
  String get settingsStatsStart => 'Start';

  @override
  String get settingsStatsEnd => 'End';

  @override
  String get settingsStatsApply => 'Apply';

  @override
  String get settingsStatsWeekdayTue => 'Tue';

  @override
  String get settingsStatsWeekdayThu => 'Thu';

  @override
  String get settingsStatsWeekdaySat => 'Sat';

  @override
  String get settingsStatsWeekdaySun => 'Sun';

  @override
  String settingsScanFailed(Object error) {
    return 'Scan failed: $error';
  }

  @override
  String settingsCleanFailed(Object error) {
    return 'Cleanup failed: $error';
  }

  @override
  String settingsCleanPartialFailed(Object deletedCount, Object failedCount) {
    return 'Cleaned $deletedCount images; $failedCount failed to delete.';
  }

  @override
  String get settingsCleanNoFiles =>
      'Image references have changed; no files were deleted.';

  @override
  String settingsCleanSkipped(Object deletedCount, Object skippedCount) {
    return 'Cleaned $deletedCount images; $skippedCount kept because references changed.';
  }

  @override
  String settingsCleanDone(Object deletedCount, Object freedSize) {
    return 'Cleaned $deletedCount images, freeing $freedSize.';
  }

  @override
  String get settingsCleaning => 'Cleaning';

  @override
  String get settingsScanning => 'Scanning';

  @override
  String get settingsImageAttachments => 'Image attachments';

  @override
  String get settingsRescan => 'Rescan';

  @override
  String get settingsCleanImages => 'Clean images';

  @override
  String get settingsNoStats => 'No statistics yet';

  @override
  String get settingsAllImages => 'All images';

  @override
  String get settingsStillInUse => 'Still in use';

  @override
  String get settingsCleanable => 'Cleanable';

  @override
  String settingsUnusedCount(Object count) {
    return 'Unused $count';
  }

  @override
  String get settingsSelectAll => 'Select all';

  @override
  String get settingsDeselectAll => 'Deselect all';

  @override
  String settingsSelectedSummary(Object count, Object size) {
    return '$count selected · $size';
  }

  @override
  String get settingsConfirmDelete => 'Confirm delete';

  @override
  String get settingsPreview => 'Preview';

  @override
  String get settingsPreviewFailed => 'Unable to preview this image';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionPreferences => 'Preferences';

  @override
  String get settingsSectionProviders => 'Providers';

  @override
  String get settingsSectionModels => 'Default models';

  @override
  String get settingsSectionHotkeys => 'Hotkeys';

  @override
  String get settingsSectionCloudSync => 'Cloud sync';

  @override
  String get settingsSectionStorage => 'Storage';

  @override
  String get settingsSectionStats => 'Stats';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsImageFileType => 'Images';

  @override
  String get settingsImageNotSelected => 'Not selected';

  @override
  String settingsImagePickFailed(Object error) {
    return 'Failed to select image: $error';
  }

  @override
  String get settingsPersonalInfoTitle => 'Personal info';

  @override
  String get settingsDailyWorkHours => 'Daily work hours';

  @override
  String get settingsHoursSuffix => 'h';

  @override
  String get settingsDailySalary => 'Daily salary';

  @override
  String get settingsIndustry => 'Industry';

  @override
  String get settingsFontDisplayTitle => 'Font & display';

  @override
  String get settingsAppFont => 'App font';

  @override
  String get settingsFontSize => 'Font size';

  @override
  String get settingsMarkdownHighlight => 'Markdown syntax highlighting';

  @override
  String get settingsBehaviorTitle => 'Behavior & startup';

  @override
  String get settingsAutoStart => 'Launch at startup';

  @override
  String get settingsShowUpdates => 'Show updates';

  @override
  String get settingsApiLog => 'Log API network requests';

  @override
  String get settingsWallpaperTitle => 'Wallpaper';

  @override
  String get settingsWallpaperMode => 'Mode';

  @override
  String get settingsWallpaperModeDefault => 'Default background';

  @override
  String get settingsWallpaperModeImage => 'Local image';

  @override
  String get settingsWallpaperModeSolid => 'Solid color';

  @override
  String get settingsSelectImage => 'Select image';

  @override
  String get settingsWallpaperFill => 'Fill';

  @override
  String get settingsWallpaperFillStretch => 'Stretch';

  @override
  String get settingsWallpaperFillCover => 'Cover';

  @override
  String get settingsWallpaperFillCenter => 'Center';

  @override
  String get settingsBackgroundColor => 'Background color';

  @override
  String get settingsOpacity => 'Opacity';

  @override
  String get settingsBlur => 'Blur';

  @override
  String get settingsMaskOpacity => 'Mask intensity';

  @override
  String get settingsTransparentControls => 'Transparent controls';

  @override
  String get settingsControlOpacity => 'Control opacity';

  @override
  String get settingsShowBorders => 'Keep card borders';

  @override
  String get settingsTextContrast => 'Darken text color';

  @override
  String get settingsTrayTitle => 'Tray';

  @override
  String get settingsShowTrayIcon => 'Show tray icon';

  @override
  String get settingsCloseToTray => 'Minimize to tray on close';

  @override
  String get settingsDataSaveTitle => 'Data storage';

  @override
  String get settingsComponentTitle => 'Widget settings';

  @override
  String get settingsShowDesktopWidget => 'Show desktop widget';

  @override
  String get settingsOrbMode => 'Desktop widget orb mode';

  @override
  String get settingsWidgetWallpaperTitle => 'Widget wallpaper';

  @override
  String get settingsWidgetWallpaperModeDefaultWhite => 'Default white';

  @override
  String get settingsPromptTitle => 'Prompts';

  @override
  String get settingsHomeSections => 'Home sections';

  @override
  String get settingsDailyMergePrompt => 'Daily merge';

  @override
  String get settingsGlobalSignPrompt => 'Global sign';

  @override
  String get settingsEditDailyMergePromptTitle => 'Edit daily merge prompt';

  @override
  String get settingsDailyMergePromptHint => 'Enter daily merge Prompt...';

  @override
  String get settingsEditGlobalSignPromptTitle => 'Edit global sign prompt';

  @override
  String get settingsGlobalSignPromptHint => 'Enter global sign Prompt...';

  @override
  String get settingsVariableCurrentDate => 'Current date';

  @override
  String get settingsVariableExistingDailyContent =>
      'Existing daily note content';

  @override
  String get settingsVariableRawInput => 'New quick note';

  @override
  String get settingsVariableIndustry => 'User\'s industry';

  @override
  String get settingsVariableDailyContent => 'Today\'s daily note content';

  @override
  String get settingsVariableGlobalSignJson => 'Current global sign JSON';

  @override
  String get settingsMemoryTitle => 'Memory book search';

  @override
  String get settingsMemorySearchLimit => 'Max searches per memory round';

  @override
  String get settingsTimesSuffix => 'times';

  @override
  String get settingsMemoryResultMaxChars => 'Max characters per result';

  @override
  String get settingsCharsSuffix => 'chars';

  @override
  String get settingsMemoryWeekDailyLimit => 'Max consecutive daily notes';

  @override
  String get settingsItemsSuffix => 'items';

  @override
  String get settingsMemoryKeywordSearchLimit => 'Max keyword search results';

  @override
  String get settingsMemoryKeywordBefore =>
      'Max characters before matched keyword';

  @override
  String get settingsMemoryKeywordAfter =>
      'Max characters after matched keyword';

  @override
  String settingsConfigFileLabel(Object path) {
    return 'Config file: $path';
  }

  @override
  String get settingsPlatformNotSupported => 'Not supported on this platform';

  @override
  String get settingsDataMigrationComplete => 'Data migration complete';

  @override
  String get settingsDataMigrationDetail =>
      'Successfully switched to the new data directory.\nAfter confirming everything works, delete the old directory to free up space.';

  @override
  String get settingsSectionTitleHeader => 'Title';

  @override
  String get settingsAiInstructionHeader => 'AI instructions';

  @override
  String get settingsSectionTitleHint => 'Section title';

  @override
  String get settingsSectionInstructionHint =>
      'Describe the categorization rules';

  @override
  String get settingsFimReady => 'AI real-time completion ready';

  @override
  String get settingsFimPredicting => 'AI completion in progress';

  @override
  String get settingsFimAcceptHint =>
      'Tab all · Ctrl+L line · Ctrl+K character';

  @override
  String settingsFimNotTriggered(Object reason) {
    return 'FIM not triggered: $reason';
  }

  @override
  String settingsFimRequestFailed(Object error) {
    return 'FIM request failed: $error';
  }

  @override
  String get settingsFimNoPrediction =>
      'FIM requested, but no prediction available';

  @override
  String get settingsSelectThisFolder => 'Select this folder';

  @override
  String get settingsSaveDirectory => 'Save directory';

  @override
  String get settingsDataDirectoryHint => 'Current save directory';

  @override
  String get settingsSelectMigrateDirectory => 'Select and migrate directory';

  @override
  String get settingsRestoreDefaultDirectory => 'Restore default directory';

  @override
  String get settingsSystemDefault => 'System default';

  @override
  String get settingsResetFont => 'Reset font';

  @override
  String get settingsSelectFont => 'Select font';

  @override
  String get settingsSearchSystemFonts => 'Search system fonts';

  @override
  String get settingsNoMatchingFonts => 'No matching fonts';

  @override
  String get settingsAppearanceMode => 'Appearance mode';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsProtocol => 'Protocol';

  @override
  String get settingsDisabled => 'Disabled';

  @override
  String get settingsEmptyProviderDetails =>
      'Add a provider to edit its configuration here';

  @override
  String get settingsSelectColor => 'Select color';

  @override
  String get settingsModelIntelligent => 'Intelligent generation model';

  @override
  String get settingsModelIntelligentDesc =>
      'Structures quick notes from the home page and merges them into the daily note.';

  @override
  String get settingsModelEditCompletion => 'Edit completion model';

  @override
  String get settingsModelEditCompletionDesc =>
      'Used for note completion. When the model supports completion, defaults to the completions FIM API.';

  @override
  String get settingsModelMemoryBook => 'Memory book model';

  @override
  String get settingsModelMemoryBookDesc =>
      'Answers questions and searches history in the memory book.';

  @override
  String get settingsModelUnset => 'Not';

  @override
  String get settingsModelSet => 'Set';

  @override
  String get settingsNoModelSelected => 'No model selected';

  @override
  String get settingsSelectModelByProvider =>
      'Select default models by provider';

  @override
  String get settingsNotSelected => 'Not selected';

  @override
  String get settingsGlobalHotkeysTitle => 'Global hotkeys';

  @override
  String get settingsShowHidePage => 'Show/Hide page';

  @override
  String get settingsReset => 'Reset';

  @override
  String get settingsInputShortcutsTitle => 'Input shortcuts';

  @override
  String get settingsSendMessage => 'Send message';

  @override
  String get settingsHotkeyNotSupported => 'This key is not supported';

  @override
  String get settingsHotkeyNeedModifiersMac =>
      'Must include Cmd, Ctrl, Option, or Shift';

  @override
  String get settingsHotkeyNeedModifiersWin =>
      'Must include Ctrl, Alt, Shift, or Win';

  @override
  String get settingsHotkeyPressHint => 'Press a shortcut';

  @override
  String get settingsHotkeyNotSet => 'Not set';

  @override
  String get settingsAppTagline =>
      'AI-powered smart notes and daily report generator';

  @override
  String get settingsCheckForUpdates => 'Check for updates';

  @override
  String get settingsWebsite => 'Website';

  @override
  String get settingsLicense => 'License';

  @override
  String get settingsJoinQQGroup => 'Join QQ group';

  @override
  String get settingsCheckingForUpdates => 'Checking for updates...';

  @override
  String get settingsUpdateContentUnavailable =>
      'Unable to read update details right now';

  @override
  String get settingsAlreadyUpToDate => 'You\'re on the latest version';

  @override
  String get settingsUpdateCheckFailed =>
      'Unable to check for updates, please try again later';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsUnknown => 'Unknown';

  @override
  String settingsSelectModelTitled(Object title) {
    return 'Select $title';
  }

  @override
  String get notesKindDaily => 'Daily';

  @override
  String get notesKindWeekly => 'Weekly';

  @override
  String get notesKindMonthly => 'Monthly';

  @override
  String get settingsMigrationErrorNested =>
      'The save directory cannot be inside the current data directory.';

  @override
  String get settingsMigrationErrorIsFile =>
      'The save directory cannot be a file.';

  @override
  String get settingsMigrationErrorMacAccess =>
      'Failed to save the macOS folder access permission. Please choose the save directory again.';

  @override
  String settingsImageUnsupportedFormat(Object extension) {
    return 'Unsupported image format: $extension';
  }

  @override
  String get settingsImageSourceMissing => 'The source image no longer exists.';

  @override
  String get settingsProviderApiKeyEmpty => 'The provider API key is empty.';

  @override
  String get settingsWeeklyReportPrompt => 'Weekly report';

  @override
  String get settingsEditWeeklyReportPromptTitle => 'Edit weekly report prompt';

  @override
  String get settingsWeeklyReportPromptHint => 'Enter weekly report Prompt...';

  @override
  String get settingsVariablePeriodLabel => 'Report period';

  @override
  String get settingsVariableSourceMarkdown => 'Daily notes of the week';

  @override
  String get memoryToolLabelResolveIsoWeek => 'Resolve ISO week dates';

  @override
  String get memoryToolLabelRunToolBatch => 'Run tools in batch';

  @override
  String get memoryToolLabelRunToolSequence => 'Run tools in sequence';

  @override
  String get memoryImageCountLimit => 'Up to 4 images per message.';

  @override
  String get memoryImageInvalid =>
      'Only png, jpg, webp or gif images up to 5 MB are supported.';

  @override
  String get memoryImageModelUnsupported =>
      'The selected memory model does not support image input.';

  @override
  String get memoryImageSaveFailed =>
      'Failed to save the images. Please try again.';
}
