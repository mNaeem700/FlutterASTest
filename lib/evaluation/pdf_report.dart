import 'dart:convert';

/// A small text-only PDF writer, enough for the run summary of Docs 2 and 3
/// without a new dependency. Only Latin-1 text can be shown; other characters
/// become `?`.
class PdfReport {
  const PdfReport();

  static const _linesPerPage = 52;

  List<int> build(String title, List<String> lines) {
    final all = [title, '', ...lines];
    final pages = [
      for (var i = 0; i < all.length; i += _linesPerPage)
        all.sublist(i, i + _linesPerPage > all.length ? all.length : i + _linesPerPage),
    ];

    // Objects: 1 catalog, 2 page tree, 3 font, then a page and its content.
    final objects = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Count ${pages.length} /Kids [${[
        for (var i = 0; i < pages.length; i++) '${4 + i * 2} 0 R',
      ].join(' ')}] >>',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
    ];
    for (var i = 0; i < pages.length; i++) {
      final content = StringBuffer('BT /F1 9 Tf 40 800 Td 14 TL\n');
      for (final line in pages[i]) {
        content.writeln('(${_escape(line)}) Tj T*');
      }
      content.write('ET');
      final stream = content.toString();
      objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
          '/Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>');
      objects.add('<< /Length ${latin1.encode(stream).length} >>\nstream\n$stream\nendstream');
    }

    final out = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(latin1.encode(out.toString()).length);
      out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xref = latin1.encode(out.toString()).length;
    out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
    for (final offset in offsets) {
      out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    return latin1.encode(out.toString());
  }

  static String _escape(String text) {
    final safe = String.fromCharCodes(text.runes.map((c) => c > 255 ? 63 : c));
    final clipped = safe.length > 100 ? safe.substring(0, 100) : safe;
    return clipped.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
  }
}
