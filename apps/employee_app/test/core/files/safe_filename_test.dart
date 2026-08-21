import 'package:employee_app/core/files/safe_filename.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects C0 C1 and all supported Unicode format ranges', () {
    const rejectedRunes = [
      0x0000,
      0x001F,
      0x007F,
      0x009F,
      0x00AD,
      0x0600,
      0x0605,
      0x061C,
      0x06DD,
      0x070F,
      0x0890,
      0x0891,
      0x08E2,
      0x180E,
      0x200B,
      0x200F,
      0x202A,
      0x202E,
      0x2060,
      0x2064,
      0x2066,
      0x206F,
      0xFEFF,
      0xFFF9,
      0xFFFB,
      0x110BD,
      0x110CD,
      0x13430,
      0x1343F,
      0x1BCA0,
      0x1BCA3,
      0x1D173,
      0x1D17A,
      0xE0001,
      0xE0020,
      0xE007F,
    ];

    for (final rune in rejectedRunes) {
      expect(
        SafeFilenamePolicy.isSafe(
          '合同${String.fromCharCode(rune)}.pdf',
          allowedExtensions: const {'pdf'},
        ),
        isFalse,
        reason: 'accepted U+${rune.toRadixString(16).toUpperCase()}',
      );
    }
  });

  test('preserves a safe Unicode basename and normalizes its extension', () {
    const filename = '员工合同扫描.PDF';

    expect(
      SafeFilenamePolicy.isSafe(filename, allowedExtensions: const {'pdf'}),
      isTrue,
    );
    expect(SafeFilenamePolicy.extensionOf(filename), 'pdf');
    expect(SafeFilenamePolicy.basename('C:\\safe\\$filename'), filename);
  });

  test('accepts internal double dots without a path separator', () {
    const filename = '合同..😀.DOCX';

    expect(
      SafeFilenamePolicy.isSafe(filename, allowedExtensions: const {'docx'}),
      isTrue,
    );
  });

  test('uses Unicode scalar length to match the backend 255 limit', () {
    final filename = '${List.filled(251, '😀').join()}.pdf';

    expect(filename.runes.length, 255);
    expect(
      SafeFilenamePolicy.isSafe(filename, allowedExtensions: const {'pdf'}),
      isTrue,
    );
  });
}
