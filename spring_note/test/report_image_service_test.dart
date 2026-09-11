import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/services/report_image_service.dart';

void main() {
  const service = ReportImageService();

  late Directory root;
  late String notesRoot;
  late String dailyDir;
  late String imagesDir;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'springnote-report-image-test-',
    );
    notesRoot = root.path;
    dailyDir = _join(notesRoot, 'daily');
    imagesDir = _join(notesRoot, 'images');
    await Directory(dailyDir).create(recursive: true);
    await Directory(imagesDir).create(recursive: true);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<void> writeImage(String name, {int byteCount = 8}) async {
    await File(_join(imagesDir, name)).writeAsBytes(
      List<int>.filled(byteCount, 1),
    );
  }

  Future<void> writeNote(String name, String content) async {
    await File(_join(dailyDir, name)).writeAsString(content);
  }

  List<String> notePaths(List<String> names) =>
      [for (final name in names) _join(dailyDir, name)];

  test('按笔记内文档顺序提取引用的图片', () async {
    await writeImage('a.png');
    await writeImage('b.jpg');
    await writeNote('2026-07-21.md', '![a](../images/a.png)\n![b](../images/b.jpg)\n');

    final images = await service.collect(
      notePathsNewestFirst: notePaths(['2026-07-21.md']),
      notesRootDirectory: notesRoot,
    );

    expect(images.map((image) => image.name), ['a.png', 'b.jpg']);
    expect(images.first.mimeType, 'image/png');
    expect(images.last.mimeType, 'image/jpeg');
    expect(images.first.bytes, hasLength(8));
  });

  test('跨笔记按解析后的完整路径去重', () async {
    await writeImage('shared.png');
    await writeImage('extra.png');
    await writeNote('2026-07-22.md', '![x](../images/shared.png)\n');
    await writeNote(
      '2026-07-21.md',
      '![y](../images/./shared.png)\n![z](../images/extra.png)\n',
    );

    final images = await service.collect(
      notePathsNewestFirst: notePaths(['2026-07-22.md', '2026-07-21.md']),
      notesRootDirectory: notesRoot,
    );

    expect(images.map((image) => image.name), ['shared.png', 'extra.png']);
  });

  test('超过 10 张时取最新笔记中的前 10 张', () async {
    for (var index = 0; index < 12; index++) {
      await writeImage('n$index.png');
    }
    await writeImage('old.png');
    final references = [
      for (var index = 0; index < 12; index++) '![n$index](../images/n$index.png)',
    ].join('\n');
    await writeNote('2026-07-22.md', '$references\n');
    await writeNote('2026-07-21.md', '![old](../images/old.png)\n');

    final images = await service.collect(
      notePathsNewestFirst: notePaths(['2026-07-22.md', '2026-07-21.md']),
      notesRootDirectory: notesRoot,
    );

    expect(images.map((image) => image.name), [
      'n0.png',
      'n1.png',
      'n2.png',
      'n3.png',
      'n4.png',
      'n5.png',
      'n6.png',
      'n7.png',
      'n8.png',
      'n9.png',
    ]);
  });

  test('日期从近到远时，新笔记的图片排在前面', () async {
    await writeImage('newest.png');
    await writeImage('oldest.png');
    await writeNote('2026-07-20.md', '![o](../images/oldest.png)\n');
    await writeNote('2026-07-22.md', '![n](../images/newest.png)\n');

    final images = await service.collect(
      notePathsNewestFirst: notePaths(['2026-07-22.md', '2026-07-20.md']),
      notesRootDirectory: notesRoot,
    );

    expect(images.map((image) => image.name), ['newest.png', 'oldest.png']);
  });

  test('过滤超过 5MB、不支持的格式与缺失文件', () async {
    await writeImage('big.png', byteCount: 5 * 1024 * 1024 + 1);
    await writeImage('chart.svg');
    await writeImage('empty.png', byteCount: 0);
    await writeImage('ok.webp');
    await writeNote(
      '2026-07-21.md',
      '![big](../images/big.png)\n'
      '![svg](../images/chart.svg)\n'
      '![empty](../images/empty.png)\n'
      '![missing](../images/missing.png)\n'
      '![ok](../images/ok.webp)\n',
    );

    final images = await service.collect(
      notePathsNewestFirst: notePaths(['2026-07-21.md']),
      notesRootDirectory: notesRoot,
    );

    expect(images.map((image) => image.name), ['ok.webp']);
    expect(images.single.mimeType, 'image/webp');
  });

  test('拒绝 images 目录之外的越界与外部目标', () async {
    await File(_join(notesRoot, 'outside.png')).writeAsBytes([1, 2, 3]);
    await writeImage('inside.png');
    await writeNote(
      '2026-07-21.md',
      '![outside](../outside.png)\n'
      '![escape](../../outside.png)\n'
      '![abs](/tmp/evil.png)\n'
      '![web](https://example.com/x.png)\n'
      '![file](file:///tmp/x.png)\n'
      '![inside](../images/inside.png)\n',
    );

    final images = await service.collect(
      notePathsNewestFirst: notePaths(['2026-07-21.md']),
      notesRootDirectory: notesRoot,
    );

    expect(images.map((image) => image.name), ['inside.png']);
  });

  test('笔记不存在或无法解析时静默返回空列表', () async {
    final images = await service.collect(
      notePathsNewestFirst: notePaths(['2026-07-21.md']),
      notesRootDirectory: notesRoot,
    );

    expect(images, isEmpty);
  });
}

String _join(String left, String right) =>
    '$left${Platform.pathSeparator}$right';
