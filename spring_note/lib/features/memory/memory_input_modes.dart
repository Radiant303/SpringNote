import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';

/// A composer input mode: a tag the user inserts into the input text from
/// the "+" menu. The tag is stored as a single private-use code point so it
/// behaves like one character — the cursor steps over it and Backspace or
/// Delete removes it whole — while [MemoryComposerController] paints it as
/// a labeled chip. Mode state is therefore derived purely from the text:
/// deleting the tag disables the mode, with no separate global state.
class MemoryInputMode {
  const MemoryInputMode({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.token,
    required this.prompt,
  });

  /// Stable identifier, e.g. `springtree`.
  final String id;

  /// Tag label shown inside the input field, e.g. `思维导图`.
  final String label;

  /// Short muted hint shown next to the label in the "+" menu.
  final String description;

  /// Icon shown in the "+" menu and in the input-field tag.
  final IconData icon;

  /// Single private-use code point embedded in the input text.
  final String token;

  /// Prompt appended to the model request while the tag is present.
  final String prompt;
}

/// Mind-map mode: the model answers with a single ```springtree block.
const MemoryInputMode mindMapInputMode = MemoryInputMode(
  id: 'springtree',
  label: '思维导图',
  description: '以思维导图呈现回答',
  icon: Icons.account_tree_outlined,
  token: '\u{e100}',
  prompt: r'''
  你当前处于 SpringTree 输出模式。
  请根据用户请求生成内容，并将最终响应转换为 springtree 格式输出。
  输出要求：
  1. 最终只能输出一个 Markdown 代码块。
  2. 代码块语言必须为 springtree。
  3. 不允许输出任何解释文字、标题、说明或总结。
  4. 不允许使用表格、JSON 或其他格式。
  5. 输出内容必须严格符合 springtree 树结构格式。
  6. 必须保证输出存在唯一根节点（主标题），所有内容必须挂载在该根节点下。
  springtree 格式规范：
  * springtree 是一种基于 Markdown 无序列表实现的树形结构格式。
  * 每一行表示一个节点。
  * 使用 "-" 表示节点。
  * 使用缩进表示节点层级关系。
  * 节点层级根据内容关系自动组织。
  * 父节点表示上层概念或分类。
  * 子节点表示具体内容。
  * 更深层级表示详细信息。
  根节点（主标题）规则：
  * 最终输出必须包含且只能包含一个根节点。
  * 根节点必须位于整个 springtree 的第一行。
  * 第一行必须是主标题，禁止第一行直接输出分类节点或具体事项。
  * 所有其他节点必须作为根节点的子节点存在。
  * 不允许出现多个并列顶层节点。
  * 根节点名称必须根据用户请求自动生成。
  * 如果用户未提供标题，必须根据内容生成合理的主标题。
  * 根节点应优先使用以下类型：
    - 日期（如：2026-07-26 日报、2026-07 月度总结）
    - 主题名称（如：人工智能生态系统）
    - 项目名称（如：SpringNote 项目开发）
    - 核心概念（如：机器学习知识体系）
  * 根节点不得为空。
  * 根节点不得使用无意义名称，例如：
    - 内容
    - 列表
    - 信息
    - 数据
    - 总结
    - 未命名
  生成规则：
  * 根据用户请求生成对应内容。
  * 对内容进行合理分层组织。
  * 保留关键名称、时间、事项、细节等有效信息。
  * 合并重复内容。
  * 删除无意义描述。
  * 不编造不存在的信息。
  * 保证输出结构稳定，方便程序解析。
  * 根据语义关系决定节点层级，而不是简单按照原文排列。
  * 相同类型内容应归入同一父节点。
  * 相关内容应尽量靠近，避免跨层级分散。
  * 重要概念作为父节点，具体事项作为子节点。
  * 细节信息放在更深层级。
  层级规则：
  * 第一层：根节点（主标题）。
  * 第二层：主要分类、模块、阶段、领域。
  * 第三层：具体项目、功能、任务、对象。
  * 第四层及以下：详细描述、子任务、属性、步骤、说明。
  * 不允许跳过根节点直接输出第二层内容。
  * 不允许出现无法归属到父节点的孤立节点。
  内容处理规则：
  * 如果用户输入的是列表，将其转换为树形结构。
  * 如果用户输入的是文章，将其提取核心结构转换为树形结构。
  * 如果用户输入的是多个主题，将它们归类到同一个根节点下。
  * 如果用户输入包含时间信息，应保留时间信息。
  * 如果用户输入包含项目、技术、人物、事件等名称，应保留原始名称。
  * 不要为了增加层级而强行拆分无意义节点。
  * 保持树结构清晰、自然、可读。
  示例：
  ```springtree
  - 2026-07-26 周报
    - 项目开发
      - SpringNote
        - 完成 xxx 功能
        - 优化 xxx 模块
    - 技术研究
      - MCP
        - 调试 xxx 流程
  ```
  错误示例：
  ```springtree
  - 项目开发
    - SpringNote
  - 技术研究
    - MCP
  ```
  错误原因：
  缺少唯一根节点，存在多个顶层节点。
  正确示例：
  ```springtree
  - 2026-07-26 工作总结
    - 项目开发
      - SpringNote
        - 完成功能开发
    - 技术研究
      - MCP
        - 调试接口流程
  ```
  最终输出格式：
  ```springtree
  - 主标题
    - 分类
      - 内容
  ```
  除上述 springtree 代码块外，不允许输出任何其他内容。
  ''',
);

/// Every composer input mode. Future modes only need a new entry here.
const List<MemoryInputMode> memoryInputModes = [mindMapInputMode];

/// The result of resolving mode tags inside an input string.
class MemoryInputModeResolution {
  const MemoryInputModeResolution({
    required this.userText,
    required this.modes,
  });

  /// The input with every mode tag removed — what the user actually typed.
  final String userText;

  /// Active modes in registry order (one entry per mode, duplicates folded).
  final List<MemoryInputMode> modes;

  /// The joined prompts of all active modes, for the model request.
  String get promptSuffix => modes.map((mode) => mode.prompt).join('\n\n');
}

/// Resolves stored mode ids to registered modes, keeping registry order
/// and skipping unknown ids (e.g. a mode removed by a newer app version).
List<MemoryInputMode> memoryInputModesForIds(List<String> ids) => [
  for (final mode in memoryInputModes)
    if (ids.contains(mode.id)) mode,
];

/// Localized tag label for [mode], shown inside the input field and the
/// "+" menu. Falls back to [MemoryInputMode.label] (the model-facing name)
/// for modes without a UI string yet.
String memoryInputModeLabel(BuildContext context, MemoryInputMode mode) {
  return switch (mode.id) {
    'springtree' => l10n(context).memoryInputModeMindMapLabel,
    _ => mode.label,
  };
}

/// Localized muted hint for [mode], shown next to the label in the "+" menu.
String memoryInputModeDescription(BuildContext context, MemoryInputMode mode) {
  return switch (mode.id) {
    'springtree' => l10n(context).memoryInputModeMindMapDescription,
    _ => mode.description,
  };
}

/// Note appended (request view only) to a past user message that was sent
/// with [modes] active, so the model knows the following reply's special
/// format was tag-driven rather than the default way to answer.
String modeRequestNote(Iterable<MemoryInputMode> modes) {
  final labels = modes.map((mode) => '「${mode.label}」').join('、');
  return '（本条消息发送时选择了 $labels 模式，当次回答使用了该模式要求的特殊格式。）';
}

/// Reminder appended (request view only) to the latest user message when the
/// history contains mode-forced replies but the current message carries no
/// mode tag. Refers to [modes] by label so it stays valid for modes whose
/// forced format is not a code fence.
String noModeReplyReminder(Iterable<MemoryInputMode> modes) {
  final labels = modes.map((mode) => '「${mode.label}」').join('、');
  return '（本条消息未选择任何输出模式，请用普通文字回答，'
      '不要沿用此前 $labels 回答中的特殊格式。）';
}

/// Strips mode tags from [input] and collects the modes they activate.
MemoryInputModeResolution resolveMemoryInputModes(String input) {
  final active = <MemoryInputMode>[];
  var userText = input;
  for (final mode in memoryInputModes) {
    if (userText.contains(mode.token)) {
      active.add(mode);
      userText = userText.replaceAll(mode.token, '');
    }
  }
  return MemoryInputModeResolution(userText: userText, modes: active);
}

/// Text controller that paints registered mode tokens as inline tags.
///
/// Each token is one code point in the text, so selection, cursor movement
/// and deletion treat it atomically; only the visual rendering differs —
/// a small icon plus a colored label, like the tags in chat composers.
class MemoryComposerController extends TextEditingController {
  static const Color _tagColor = Color(0xFF3B82F6);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final tagStyle = base.copyWith(color: _tagColor);
    final iconSize = (base.fontSize ?? 14) + 2;

    final spans = <InlineSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      var nearest = -1;
      MemoryInputMode? nearestMode;
      for (final mode in memoryInputModes) {
        final index = rest.indexOf(mode.token);
        if (index >= 0 && (nearest < 0 || index < nearest)) {
          nearest = index;
          nearestMode = mode;
        }
      }
      if (nearestMode == null) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (nearest > 0) {
        spans.add(TextSpan(text: rest.substring(0, nearest)));
      }
      // The whole tag renders as ONE placeholder: it occupies exactly one
      // code unit, matching the token's length. Painting it as separate
      // icon+text spans would make the paragraph longer than the text and
      // the caret would land in the middle of the label instead of after
      // the tag.
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(nearestMode.icon, size: iconSize, color: _tagColor),
              const SizedBox(width: 3),
              Text(memoryInputModeLabel(context, nearestMode), style: tagStyle),
              const SizedBox(width: 4),
            ],
          ),
        ),
      );
      rest = rest.substring(nearest + nearestMode.token.length);
    }
    return TextSpan(style: base, children: spans);
  }
}
