abstract final class StructuredNoteSectionIds {
  static const a = 'oa';
  static const b = 'ob';
  static const c = 'oc';
  static const values = [a, b, c];
}

class StructuredWorkNoteSection {
  const StructuredWorkNoteSection({required this.id, required this.items});

  final String id;
  final List<String> items;
}

class StructuredWorkNote {
  const StructuredWorkNote({required this.rawInput, required this.sections});

  final String rawInput;
  final List<StructuredWorkNoteSection> sections;

  List<String> itemsFor(String id) {
    for (final section in sections) {
      if (section.id == id) {
        return section.items;
      }
    }
    return const [];
  }

  StructuredWorkNote mergeWithOlder(StructuredWorkNote older) {
    return StructuredWorkNote(
      rawInput: rawInput,
      sections: [
        for (final id in StructuredNoteSectionIds.values)
          StructuredWorkNoteSection(
            id: id,
            items: [...itemsFor(id), ...older.itemsFor(id)],
          ),
      ],
    );
  }

  bool get isEmpty => sections.every((section) => section.items.isEmpty);

  static const empty = StructuredWorkNote(
    rawInput: '',
    sections: [
      StructuredWorkNoteSection(id: StructuredNoteSectionIds.a, items: []),
      StructuredWorkNoteSection(id: StructuredNoteSectionIds.b, items: []),
      StructuredWorkNoteSection(id: StructuredNoteSectionIds.c, items: []),
    ],
  );
}
