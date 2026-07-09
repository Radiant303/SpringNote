import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/custom_divider.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:spring_note/core/services/update_check_service.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/core/widgets/spring_markdown.dart';
import 'package:spring_note/core/widgets/update_dialog.dart';

void main() {
  testWidgets('update changelog uses shared markdown rendering', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: AppUpdateDialog(
            updateCheckService: _NoopUpdateCheckService(),
            currentVersion: '1.0.0',
            latest: AppUpdateInfo(
              version: '1.1.0',
              changeTime: '2026-07-09',
              downloadUrl: 'https://example.com/SpringNote.exe',
              changelog:
                  '# 更新内容\n\n'
                  '- [x] 修复渲染\n\n'
                  '---\n\n'
                  '| 功能 | 说明 |\n'
                  '|---|---|\n'
                  '| `代码` | 表格 |\n\n'
                  r'\[E = mc^2\]'
                  '\n\n'
                  '![chart](images/chart.png)',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final markdown = tester.widget<GptMarkdown>(find.byType(GptMarkdown));
    final markdownTheme = tester.widget<GptMarkdownTheme>(
      find.byType(GptMarkdownTheme),
    );
    final dividers = tester.widgetList<CustomDivider>(
      find.byType(CustomDivider),
    );

    expect(markdown.style?.color, const Color(0xFF333333));
    expect(markdown.onLinkTap, same(openSpringMarkdownLink));
    expect(markdownTheme.gptThemeData.h1?.color, const Color(0xFF333333));
    expect(markdownTheme.gptThemeData.h1?.height, 0.92);
    expect(markdownTheme.gptThemeData.hrLineThickness, 1);
    expect(markdownTheme.gptThemeData.hrLineColor, const Color(0xFFEEEEEE));
    expect(
      dividers.any(
        (divider) =>
            divider.height == 1 && divider.color == const Color(0xFFEEEEEE),
      ),
      isTrue,
    );
    expect(find.byType(Checkbox), findsNothing);
    expect(
      find.byKey(const ValueKey('markdown-task-checkbox-checked')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('markdown-inline-code')), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown-display-math')), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown-image-frame')), findsOneWidget);
  });
}

class _NoopUpdateCheckService extends UpdateCheckService {
  const _NoopUpdateCheckService();

  @override
  Future<UpdateCheckResult> check({
    UpdateCheckMode mode = UpdateCheckMode.background,
  }) async {
    return UpdateCheckResult.idle;
  }

  @override
  Future<void> installUpdate(
    AppUpdateInfo latest, {
    void Function(UpdateInstallProgress progress)? onProgress,
  }) async {}
}
