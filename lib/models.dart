int _n = 0;
String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_n++}';

/// One item on a label. Units are millimetres.
class LabelElement {
  String id, kind, data, codeType; // kind: text | barcode | qr
  double x, y, w, h, fontSize;
  double numFontSize; // barcode number text size in mm, 0 = auto
  bool bold, showText;
  LabelElement({
    required this.id,
    required this.kind,
    required this.data,
    this.codeType = 'code128',
    this.x = 2,
    this.y = 2,
    this.w = 30,
    this.h = 8,
    this.fontSize = 4,
    this.numFontSize = 0,
    this.bold = false,
    this.showText = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'k': kind, 'd': data, 'ct': codeType,
        'x': x, 'y': y, 'w': w, 'h': h, 'fs': fontSize, 'nfs': numFontSize,
        'b': bold, 'st': showText,
      };

  factory LabelElement.fromJson(Map<String, dynamic> j) => LabelElement(
        id: j['id'], kind: j['k'], data: j['d'], codeType: j['ct'] ?? 'code128',
        x: (j['x'] as num).toDouble(), y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(), h: (j['h'] as num).toDouble(),
        fontSize: (j['fs'] as num).toDouble(),
        numFontSize: (j['nfs'] as num?)?.toDouble() ?? 0,
        bold: j['b'] ?? false, showText: j['st'] ?? true,
      );
}

class LabelTemplate {
  String id, name, folder;
  double wMm, hMm;
  int updated;
  List<LabelElement> elements;
  // Data source: none | range | list | excel.  Tokens {n} / {1} {2}… in elements.
  String dataMode;
  int rangeStart, rangeEnd, rangeStep, rangePad;
  List<List<String>> rows; // used by list + excel
  LabelTemplate({
    required this.id,
    required this.name,
    this.folder = '',
    required this.wMm,
    required this.hMm,
    int? updated,
    List<LabelElement>? elements,
    this.dataMode = 'none',
    this.rangeStart = 1,
    this.rangeEnd = 10,
    this.rangeStep = 1,
    this.rangePad = 0,
    List<List<String>>? rows,
  })  : updated = updated ?? DateTime.now().millisecondsSinceEpoch,
        elements = elements ?? [],
        rows = rows ?? [];

  /// One entry per label to print. Empty = single label, no data.
  List<List<String>> generateRows() {
    switch (dataMode) {
      case 'range':
        final out = <List<String>>[];
        final step = rangeStep == 0 ? 1 : rangeStep;
        if (step > 0) {
          for (var n = rangeStart; n <= rangeEnd && out.length < 20000; n += step) {
            out.add([n.toString().padLeft(rangePad, '0')]);
          }
        } else {
          for (var n = rangeStart; n >= rangeEnd && out.length < 20000; n += step) {
            out.add([n.toString().padLeft(rangePad, '0')]);
          }
        }
        return out;
      case 'list':
      case 'excel':
        return rows;
      default:
        return [];
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'folder': folder,
        'w': wMm, 'h': hMm, 'u': updated,
        'els': elements.map((e) => e.toJson()).toList(),
        'dm': dataMode, 'rs': rangeStart, 're': rangeEnd, 'rt': rangeStep, 'rp': rangePad,
        'rows': rows,
      };

  factory LabelTemplate.fromJson(Map<String, dynamic> j) => LabelTemplate(
        id: j['id'], name: j['name'], folder: j['folder'] ?? '',
        wMm: (j['w'] as num).toDouble(), hMm: (j['h'] as num).toDouble(),
        updated: j['u'],
        elements: (j['els'] as List)
            .map((e) => LabelElement.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        dataMode: j['dm'] ?? 'none',
        rangeStart: j['rs'] ?? 1,
        rangeEnd: j['re'] ?? 10,
        rangeStep: j['rt'] ?? 1,
        rangePad: j['rp'] ?? 0,
        rows: ((j['rows'] as List?) ?? [])
            .map((r) => (r as List).map((c) => '$c').toList())
            .toList(),
      );

  LabelTemplate copy() => LabelTemplate.fromJson(toJson());
}
