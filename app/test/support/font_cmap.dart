// The characters a bundled font draws: its cmap table (formats 4 and 12),
// read straight from the .ttf, so a test can check copy against the fonts
// the app ships rather than against whatever the machine has.

import 'dart:io';
import 'dart:typed_data';

Set<int> fontCharacters(String path) {
  final d = ByteData.sublistView(File(path).readAsBytesSync());
  int u16(int o) => d.getUint16(o);
  int i16(int o) => d.getInt16(o);
  int u32(int o) => d.getUint32(o);
  final tables = <String, int>{};
  for (var i = 0; i < u16(4); i++) {
    final at = 12 + 16 * i;
    tables[String.fromCharCodes([for (var k = 0; k < 4; k++) d.getUint8(at + k)])] = u32(at + 8);
  }
  final cmap = tables['cmap']!;
  final codes = <int>{};
  for (var i = 0; i < u16(cmap + 2); i++) {
    final sub = cmap + u32(cmap + 4 + 8 * i + 4);
    switch (u16(sub)) {
      case 4:
        final segX2 = u16(sub + 6), seg = segX2 ~/ 2;
        final ends = sub + 14, starts = ends + segX2 + 2, deltas = starts + segX2, ranges = deltas + segX2;
        for (var k = 0; k < seg; k++) {
          final start = u16(starts + 2 * k), end = u16(ends + 2 * k), delta = i16(deltas + 2 * k), range = u16(ranges + 2 * k);
          for (var c = start; c <= end && c != 0xFFFF; c++) {
            var glyph = 0;
            if (range == 0) {
              glyph = (c + delta) & 0xFFFF;
            } else {
              glyph = u16(ranges + 2 * k + range + 2 * (c - start));
              if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
            }
            if (glyph != 0) codes.add(c);
          }
        }
      case 12:
        for (var g = 0; g < u32(sub + 12); g++) {
          final at = sub + 16 + 12 * g;
          for (var c = u32(at); c <= u32(at + 4); c++) {
            codes.add(c);
          }
        }
    }
  }
  return codes;
}
