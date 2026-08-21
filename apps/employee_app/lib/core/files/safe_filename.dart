abstract final class SafeFilenamePolicy {
  static String basename(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? '' : parts.last;
  }

  static String? extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot <= 0 || dot == filename.length - 1) {
      return null;
    }
    return filename.substring(dot + 1).toLowerCase();
  }

  static bool isSafe(
    String filename, {
    required Set<String> allowedExtensions,
  }) {
    if (filename.isEmpty ||
        filename.runes.length > 255 ||
        filename != filename.trim() ||
        filename == '.' ||
        filename == '..' ||
        filename.contains('/') ||
        filename.contains(r'\') ||
        filename.contains('"') ||
        filename.contains(';') ||
        filename.runes.any(_isControlOrFormatRune)) {
      return false;
    }
    final extension = extensionOf(filename);
    return extension != null &&
        allowedExtensions.any((allowed) => allowed.toLowerCase() == extension);
  }

  static bool _isControlOrFormatRune(int rune) =>
      rune <= 0x1F ||
      (rune >= 0x7F && rune <= 0x9F) ||
      rune == 0x00AD ||
      (rune >= 0x0600 && rune <= 0x0605) ||
      rune == 0x061C ||
      rune == 0x06DD ||
      rune == 0x070F ||
      (rune >= 0x0890 && rune <= 0x0891) ||
      rune == 0x08E2 ||
      rune == 0x180E ||
      (rune >= 0x200B && rune <= 0x200F) ||
      (rune >= 0x202A && rune <= 0x202E) ||
      (rune >= 0x2060 && rune <= 0x2064) ||
      (rune >= 0x2066 && rune <= 0x206F) ||
      rune == 0xFEFF ||
      (rune >= 0xFFF9 && rune <= 0xFFFB) ||
      rune == 0x110BD ||
      rune == 0x110CD ||
      (rune >= 0x13430 && rune <= 0x1343F) ||
      (rune >= 0x1BCA0 && rune <= 0x1BCA3) ||
      (rune >= 0x1D173 && rune <= 0x1D17A) ||
      rune == 0xE0001 ||
      (rune >= 0xE0020 && rune <= 0xE007F);
}
