import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/structured_work_note.dart';
import 'package:spring_note/core/services/home_overview_service.dart';

void main() {
  test('home overview service persists daily overview json', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_overview_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    const service = HomeOverviewService();
    final date = DateTime(2026, 6, 18, 10, 30);
    final overview = await service.mergeAndSaveOverview(
      appDataDir: temp.path,
      date: date,
      current: const StructuredWorkNote(
        rawInput: 'old',
        sections: [
          StructuredWorkNoteSection(
            id: StructuredNoteSectionIds.a,
            items: ['旧完成'],
          ),
          StructuredWorkNoteSection(id: StructuredNoteSectionIds.b, items: []),
          StructuredWorkNoteSection(
            id: StructuredNoteSectionIds.c,
            items: ['旧计划'],
          ),
        ],
      ),
      incoming: const StructuredWorkNote(
        rawInput: 'new',
        sections: [
          StructuredWorkNoteSection(
            id: StructuredNoteSectionIds.a,
            items: ['新完成'],
          ),
          StructuredWorkNoteSection(
            id: StructuredNoteSectionIds.b,
            items: ['新问题'],
          ),
          StructuredWorkNoteSection(id: StructuredNoteSectionIds.c, items: []),
        ],
      ),
    );

    expect(overview.itemsFor(StructuredNoteSectionIds.a), ['新完成', '旧完成']);
    expect(overview.itemsFor(StructuredNoteSectionIds.b), ['新问题']);
    expect(overview.itemsFor(StructuredNoteSectionIds.c), ['旧计划']);

    final path = service.overviewPath(temp.path, date);
    expect(path, endsWith('${Platform.pathSeparator}2026-06-18.json'));
    expect(await File(path).exists(), isTrue);
    final savedJson = jsonDecode(await File(path).readAsString()) as Map;
    expect(savedJson['schemaVersion'], 2);
    expect(savedJson['completed'], isNull);
    expect(savedJson['issues'], isNull);
    expect(savedJson['plans'], isNull);
    expect(savedJson['sections'], hasLength(3));

    final reloaded = await service.readOverview(
      appDataDir: temp.path,
      date: date,
    );
    expect(reloaded.rawInput, 'new');
    expect(reloaded.itemsFor(StructuredNoteSectionIds.a), ['新完成', '旧完成']);
    expect(reloaded.itemsFor(StructuredNoteSectionIds.b), ['新问题']);
    expect(reloaded.itemsFor(StructuredNoteSectionIds.c), ['旧计划']);
  });

  test('home overview service reads legacy daily overview json', () async {
    final temp = await Directory.systemTemp.createTemp(
      'spring_note_legacy_overview_',
    );
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    const service = HomeOverviewService();
    final date = DateTime(2026, 6, 19);
    final file = File(service.overviewPath(temp.path, date));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'date': '2026-06-19',
        'rawInput': 'legacy',
        'completed': ['旧完成'],
        'issues': ['旧问题'],
        'plans': ['旧计划'],
      }),
    );

    final overview = await service.readOverview(
      appDataDir: temp.path,
      date: date,
    );
    expect(overview.rawInput, 'legacy');
    expect(overview.itemsFor(StructuredNoteSectionIds.a), ['旧完成']);
    expect(overview.itemsFor(StructuredNoteSectionIds.b), ['旧问题']);
    expect(overview.itemsFor(StructuredNoteSectionIds.c), ['旧计划']);
  });
}
