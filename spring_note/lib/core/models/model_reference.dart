class ModelReference {
  const ModelReference({this.providerId, required this.modelId});

  static const separator = '::';

  final String? providerId;
  final String modelId;

  bool get isQualified => providerId != null && providerId!.trim().isNotEmpty;

  static String encode({required String providerId, required String modelId}) {
    return '${Uri.encodeComponent(providerId.trim())}$separator${Uri.encodeComponent(modelId.trim())}';
  }

  static ModelReference? parse(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final separatorIndex = trimmed.indexOf(separator);
    if (separatorIndex <= 0) {
      return ModelReference(modelId: trimmed);
    }

    final encodedProviderId = trimmed.substring(0, separatorIndex);
    final modelId = trimmed.substring(separatorIndex + separator.length).trim();
    if (modelId.isEmpty) {
      return null;
    }

    return ModelReference(
      providerId: Uri.decodeComponent(encodedProviderId),
      modelId: Uri.decodeComponent(modelId),
    );
  }

  bool matches({required String providerId, required String modelId}) {
    if (this.modelId != modelId) {
      return false;
    }
    return this.providerId == null || this.providerId == providerId;
  }

  String serialize() {
    final providerId = this.providerId;
    if (providerId == null || providerId.trim().isEmpty) {
      return modelId;
    }
    return encode(providerId: providerId, modelId: modelId);
  }
}
