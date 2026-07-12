enum NoteKind {
  daily(label: '日报', directoryName: 'daily', suffix: '日报'),
  weekly(label: '周报', directoryName: 'weekly', suffix: '周报'),
  monthly(label: '月报', directoryName: 'monthly', suffix: '月报');

  const NoteKind({
    required this.label,
    required this.directoryName,
    required this.suffix,
  });

  final String label;
  final String directoryName;
  final String suffix;
}

class NoteFile {
  const NoteFile({
    required this.path,
    required this.name,
    required this.title,
    required this.modifiedAt,
    required this.kind,
    this.preview = '',
    this.searchText = '',
  });

  final String path;
  final String name;
  final String title;
  final DateTime modifiedAt;
  final NoteKind kind;
  final String preview;
  final String searchText;
}
