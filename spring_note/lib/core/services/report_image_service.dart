import 'dart:io';

import 'ai_client_service.dart';

final RegExp _markdownImagePattern = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');

/// 从源笔记中收集引用的图片，供日报/周报/月报生成时随文本一起发送给
/// AI。调用方按来源日期从近到远传入笔记路径，笔记内按文档顺序提取；
/// 单张图片的解析/读取失败都静默跳过，超出上限后不再收集。
class ReportImageService {
  const ReportImageService();

  Future<List<AiImageInput>> collect({
    required List<String> notePathsNewestFirst,
    required String notesRootDirectory,
  }) async {
    final images = <AiImageInput>[];
    final seen = <String>{};
    for (final notePath in notePathsNewestFirst) {
      if (images.length >= maxAiImageInputs) {
        break;
      }
      final noteDirectory = _parentDirectory(notePath);
      if (noteDirectory == null) {
        continue;
      }
      final String markdown;
      try {
        markdown = await File(notePath).readAsString();
      } catch (_) {
        continue;
      }
      for (final match in _markdownImagePattern.allMatches(markdown)) {
        if (images.length >= maxAiImageInputs) {
          break;
        }
        final target = _normalizedTarget(match.group(1));
        if (target == null) {
          continue;
        }
        final resolved = _resolveImagePath(noteDirectory, target);
        if (resolved == null || !_isSharedImagePath(notesRootDirectory, resolved)) {
          continue;
        }
        if (!seen.add(resolved)) {
          continue;
        }
        final input = await _readImage(resolved);
        if (input != null) {
          images.add(input);
        }
      }
    }
    return images;
  }
}

String? _parentDirectory(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  if (index <= 0) {
    return null;
  }
  return normalized.substring(0, index);
}

/// 对齐 rust markdown_links.rs 的 normalized_local_target：跳过网络/绝对
/// 路径，去掉标题与查询串，percent-decode 并统一分隔符。
String? _normalizedTarget(String? raw) {
  var target = raw?.trim() ?? '';
  if (target.isEmpty) {
    return null;
  }
  if (target.startsWith('<')) {
    final end = target.indexOf('>');
    if (end < 0) {
      return null;
    }
    target = target.substring(1, end);
  } else {
    final spaceIndex = target.indexOf(RegExp(r'\s'));
    if (spaceIndex >= 0) {
      final rest = target.substring(spaceIndex).trimLeft();
      if (rest.startsWith('"') || rest.startsWith('\'') || rest.startsWith('(')) {
        target = target.substring(0, spaceIndex);
      }
    }
  }
  final queryIndex = target.indexOf('?');
  final fragmentIndex = target.indexOf('#');
  final cutoffs = <int>[
    if (queryIndex >= 0) queryIndex,
    if (fragmentIndex >= 0) fragmentIndex,
  ];
  if (cutoffs.isNotEmpty) {
    target = target.substring(0, cutoffs.reduce((a, b) => a < b ? a : b));
  }
  final lower = target.toLowerCase();
  if (target.isEmpty ||
      target.startsWith('/') ||
      target.startsWith('\\') ||
      lower.startsWith('file:') ||
      target.contains('://') ||
      target.contains(':')) {
    return null;
  }
  final String decoded;
  try {
    decoded = Uri.decodeComponent(target);
  } catch (_) {
    return null;
  }
  final normalized = decoded.replaceAll('\\', '/');
  if (normalized.isEmpty || normalized.startsWith('/') || normalized.contains('\u0000')) {
    return null;
  }
  return normalized;
}

/// 把笔记内的相对目标解析成规范化完整路径（处理 .  与 ..）；越界（解析
/// 后脱离笔记目录树）时返回 null。POSIX 下需保留开头的 /，否则解析结果
/// 会变成相对路径。
String? _resolveImagePath(String noteDirectory, String target) {
  final segments = <String>[
    for (final segment in noteDirectory.split('/'))
      if (segment.isNotEmpty) segment,
  ];
  for (final segment in target.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isEmpty) {
        return null;
      }
      segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  final joined = segments.join('/');
  return noteDirectory.startsWith('/') ? '/$joined' : joined;
}

/// 要求解析结果落在 `<notesRoot>/images/` 内，与 rust 侧共享图片的安全
/// 策略一致；Windows 路径大小写不敏感。
bool _isSharedImagePath(String notesRootDirectory, String resolvedPath) {
  final root = notesRootDirectory.replaceAll('\\', '/');
  final normalizedRoot = root.endsWith('/')
      ? root.substring(0, root.length - 1)
      : root;
  final prefix = '$normalizedRoot/images/';
  if (Platform.isWindows) {
    return resolvedPath.toLowerCase().startsWith(prefix.toLowerCase());
  }
  return resolvedPath.startsWith(prefix);
}

Future<AiImageInput?> _readImage(String path) async {
  try {
    final file = File(path);
    final length = await file.length();
    if (length <= 0 || length > maxAiImageInputBytes) {
      return null;
    }
    final name = path.split('/').last;
    final dotIndex = name.lastIndexOf('.');
    final input = AiImageInput.fromBytes(
      name: name,
      bytes: await file.readAsBytes(),
      extension: dotIndex >= 0 ? name.substring(dotIndex + 1) : '',
    );
    return isSupportedAiImageInput(input) ? input : null;
  } catch (_) {
    return null;
  }
}
