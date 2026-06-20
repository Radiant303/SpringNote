import 'dart:io';

class ExternalLinkService {
  const ExternalLinkService();

  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return false;
    }

    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url], runInShell: false);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [url], runInShell: false);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [url], runInShell: false);
        return true;
      }
    } catch (_) {
      return false;
    }

    return false;
  }
}
