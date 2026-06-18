class StructuredWorkNote {
  const StructuredWorkNote({
    required this.rawInput,
    required this.completed,
    required this.issues,
    required this.plans,
  });

  final String rawInput;
  final List<String> completed;
  final List<String> issues;
  final List<String> plans;

  bool get isEmpty => completed.isEmpty && issues.isEmpty && plans.isEmpty;
}
