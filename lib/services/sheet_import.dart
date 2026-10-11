import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Reads the first sheet of an .xlsx file (no Excel needed) into rows of text.
List<List<String>> parseXlsx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? find(String n) {
    for (final f in zip) {
      if (f.name == n) return f;
    }
    return null;
  }

  String text(ArchiveFile f) => utf8.decode(f.content as List<int>);

  final shared = <String>[];
  final ss = find('xl/sharedStrings.xml');
  if (ss != null) {
    final doc = XmlDocument.parse(text(ss));
    for (final si in doc.findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  final sheets = zip
      .where((f) => f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (sheets.isEmpty) return [];

  final doc = XmlDocument.parse(text(sheets.first));
  final rows = <List<String>>[];
  for (final row in doc.findAllElements('row')) {
    final cells = <int, String>{};
    var maxC = -1, auto = 0;
    for (final c in row.findElements('c')) {
      final r = c.getAttribute('r');
      final col = r != null ? _colIndex(r) : auto;
      auto = col + 1;
      final t = c.getAttribute('t');
      var v = '';
      if (t == 's') {
        final idx = int.tryParse(c.getElement('v')?.innerText ?? '');
        if (idx != null && idx < shared.length) v = shared[idx];
      } else if (t == 'inlineStr') {
        v = c.findAllElements('t').map((e) => e.innerText).join();
      } else {
        v = c.getElement('v')?.innerText ?? '';
        if (t == null || t == 'n') v = _num(v);
      }
      cells[col] = v;
      if (col > maxC) maxC = col;
    }
    if (maxC < 0) continue;
    rows.add([for (var i = 0; i <= maxC; i++) cells[i] ?? '']);
  }
  return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}

int _colIndex(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch >= 65 && ch <= 90) {
      n = n * 26 + (ch - 64);
    } else if (ch >= 97 && ch <= 122) {
      n = n * 26 + (ch - 96);
    } else {
      break;
    }
  }
  return n - 1;
}

String _num(String v) {
  final d = double.tryParse(v);
  if (d == null) return v;
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return v;
}

/// CSV / TSV / semicolon-separated text.
List<List<String>> parseCsv(String raw) {
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final first = text.split('\n').first;
  final delim = first.contains('\t')
      ? '\t'
      : (first.split(';').length > first.split(',').length ? ';' : ',');
  final rows = <List<String>>[];
  var row = <String>[];
  final cur = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (q) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        cur.write(ch);
      }
    } else if (ch == '"') {
      q = true;
    } else if (ch == delim) {
      row.add(cur.toString());
      cur.clear();
    } else if (ch == '\n') {
      row.add(cur.toString());
      cur.clear();
      rows.add(row);
      row = [];
    } else {
      cur.write(ch);
    }
  }
  if (cur.isNotEmpty || row.isNotEmpty) {
    row.add(cur.toString());
    rows.add(row);
  }
  return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}
