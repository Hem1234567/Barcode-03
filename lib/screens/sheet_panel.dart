import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Lays labels out on an A4 (or other) sheet and exports / prints a PDF.
class SheetPanel extends StatefulWidget {
  final LabelTemplate t;
  final int labelCount; // 0 = no data
  final Future<Uint8List?> Function(int row, int dpi) render;
  final void Function(double w, double h) onResizeLabel;
  const SheetPanel(
      {super.key,
      required this.t,
      required this.labelCount,
      required this.render,
      required this.onResizeLabel});
  @override
  State<SheetPanel> createState() => _SheetPanelState();
}

class _SheetPanelState extends State<SheetPanel> {
  static const papers = <String, (double, double)>{
    'a4': (210, 297), 'a5': (148, 210), 'a3': (297, 420), 'letter': (215.9, 279.4),
  };
  // (name, columns, rows, landscape)
  static const presets = <(String, int, int, bool)>[
    ('24 labels · 3 columns × 8 rows · A4 portrait', 3, 8, false),
    ('24 labels · 8 columns × 3 rows · A4 landscape', 8, 3, true),
    ('24 labels · 8 columns × 3 rows · A4 portrait', 8, 3, false),
    ('21 labels · 3 × 7', 3, 7, false),
    ('10 labels · 2 × 5', 2, 5, false),
    ('14 labels · 2 × 7', 2, 7, false),
    ('16 labels · 2 × 8', 2, 8, false),
    ('30 labels · 3 × 10', 3, 10, false),
    ('40 labels · 4 × 10', 4, 10, false),
    ('65 labels · 5 × 13', 5, 13, false),
  ];

  String paper = 'a4';
  bool landscape = false;
  int cols = 3, rows = 8, skip = 0, copies = 1;
  double margin = 0, gap = 0;
  bool fit = true, cutLines = false, fillPage = true;

  @override
  void initState() {
    super.initState();
    final m = Store.sheetCfg;
    paper = m['paper'] ?? paper;
    landscape = m['land'] ?? landscape;
    cols = m['cols'] ?? cols;
    rows = m['rows'] ?? rows;
    margin = (m['margin'] as num?)?.toDouble() ?? margin;
    gap = (m['gap'] as num?)?.toDouble() ?? gap;
    fit = m['fit'] ?? fit;
    cutLines = m['cut'] ?? cutLines;
  }

  void _save() => Store.saveSheetCfg({
        'paper': paper, 'land': landscape, 'cols': cols, 'rows': rows,
        'margin': margin, 'gap': gap, 'fit': fit, 'cut': cutLines,
      });

  void _set(VoidCallback f) {
    setState(f);
    _save();
  }

  double get pageW => landscape ? papers[paper]!.$2 : papers[paper]!.$1;
  double get pageH => landscape ? papers[paper]!.$1 : papers[paper]!.$2;
  double get cellW => (pageW - 2 * margin - (cols - 1) * gap) / cols;
  double get cellH => (pageH - 2 * margin - (rows - 1) * gap) / rows;
  int get perPage => cols * rows;
  bool get hasData => widget.labelCount > 0;
  int get itemCount => hasData
      ? widget.labelCount * copies
      : (fillPage ? math.max(1, perPage - skip) : copies);
  int get pages => ((itemCount + skip.clamp(0, perPage - 1).toInt()) / perPage).ceil();
  bool get _valid => cols > 0 && rows > 0 && cellW > 3 && cellH > 3;

  void _presets() {
    showCupertinoModalPopup(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: const Text('Sheet layout'),
        actions: [
          for (final p in presets)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(c);
                _set(() {
                  cols = p.$2;
                  rows = p.$3;
                  landscape = p.$4;
                  margin = 0;
                  gap = 0;
                  skip = 0;
                });
              },
              child: Text(p.$1, style: const TextStyle(fontSize: 15)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
      ),
    );
  }

  Future<Uint8List?> _buildPdf() async {
    if (!_valid) {
      showInfo(context, 'Those settings leave no room for labels. Reduce margins or gap.');
      return null;
    }
    final unique = hasData ? widget.labelCount : 1;
    final imgs = <int, pw.MemoryImage>{};
    var cancelled = false;
    await runWithProgress(context, 'Rendering labels', unique, (report, isCancelled) async {
      for (var i = 0; i < unique; i++) {
        if (isCancelled()) {
          cancelled = true;
          return;
        }
        final png = await widget.render(i, 300);
        if (png != null) imgs[i] = pw.MemoryImage(png);
        report(i + 1);
      }
    });
    if (cancelled || imgs.isEmpty) return null;

    final items = <int>[];
    if (hasData) {
      for (var i = 0; i < unique; i++) {
        for (var c = 0; c < copies; c++) {
          items.add(i);
        }
      }
    } else {
      for (var k = 0; k < itemCount; k++) {
        items.add(0);
      }
    }

    const mm = PdfPageFormat.mm;
    final doc = pw.Document();
    var i = 0;
    var start = skip.clamp(0, perPage - 1).toInt();
    while (i < items.length) {
      final children = <pw.Widget>[];
      for (var s = start; s < perPage && i < items.length; s++, i++) {
        final x = margin + (s % cols) * (cellW + gap);
        final y = margin + (s ~/ cols) * (cellH + gap);
        final image = imgs[items[i]];
        if (image == null) continue;
        children.add(pw.Positioned(
          left: x * mm,
          top: y * mm,
          child: pw.SizedBox(
            width: cellW * mm,
            height: cellH * mm,
            child: pw.Stack(children: [
              pw.Image(image,
                  width: cellW * mm,
                  height: cellH * mm,
                  fit: fit ? pw.BoxFit.contain : pw.BoxFit.fill),
              if (cutLines)
                pw.Container(
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(width: 0.3, color: PdfColors.grey600))),
            ]),
          ),
        ));
      }
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(pageW * mm, pageH * mm, marginAll: 0),
        build: (_) => pw.Stack(children: children),
      ));
      start = 0;
    }
    return doc.save();
  }

  Future<void> _print() async {
    final bytes = await _buildPdf();
    if (bytes == null) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${widget.t.name} sheet');
  }

  Future<void> _share() async {
    final bytes = await _buildPdf();
    if (bytes == null) return;
    await Printing.sharePdf(bytes: bytes, filename: '${widget.t.name} sheet.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final text = AppColors.text(context);
    final sub = AppColors.subtext(context);

    Widget stepper(String label, int v, int min, int max, ValueChanged<int> on) => Row(children: [
          Expanded(child: Text('$label: $v', style: TextStyle(color: text))),
          CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 34,
              onPressed: v > min ? () => on(v - 1) : null,
              child: const Icon(CupertinoIcons.minus_circle)),
          CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 34,
              onPressed: v < max ? () => on(v + 1) : null,
              child: const Icon(CupertinoIcons.plus_circle)),
        ]);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        segmented<String>(context, paper,
            {'a4': 'A4', 'a5': 'A5', 'a3': 'A3', 'letter': 'Letter'},
            (v) => _set(() => paper = v)),
        const SizedBox(height: 10),
        segmented<bool>(context, landscape, {false: 'Portrait', true: 'Landscape'},
            (v) => _set(() => landscape = v)),
        const SizedBox(height: 6),
        CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _presets,
            child: const Align(
                alignment: Alignment.centerLeft,
                child: Text('Quick layouts (3 × 8, 8 × 3, …)'))),
        Row(children: [
          Expanded(
              child: NumBox(
                  label: 'Columns',
                  decimals: 0,
                  value: cols.toDouble(),
                  onChanged: (v) => _set(() => cols = v.toInt().clamp(1, 30).toInt()))),
          const SizedBox(width: 10),
          Expanded(
              child: NumBox(
                  label: 'Rows',
                  decimals: 0,
                  value: rows.toDouble(),
                  onChanged: (v) => _set(() => rows = v.toInt().clamp(1, 60).toInt()))),
          const SizedBox(width: 10),
          Expanded(
              child: NumBox(
                  label: 'Margin mm',
                  value: margin,
                  onChanged: (v) => _set(() => margin = v.clamp(0, 50).toDouble()))),
          const SizedBox(width: 10),
          Expanded(
              child: NumBox(
                  label: 'Gap mm',
                  value: gap,
                  onChanged: (v) => _set(() => gap = v.clamp(0, 30).toDouble()))),
        ]),
        const SizedBox(height: 12),

        // layout preview
        Container(
          height: 190,
          decoration: BoxDecoration(
              color: AppColors.surface(context), borderRadius: BorderRadius.circular(14)),
          child: CustomPaint(
            painter: _GridPainter(
              pageW: pageW, pageH: pageH, margin: margin, gap: gap,
              cols: cols, rows: rows, skip: skip.clamp(0, perPage - 1).toInt(),
              used: math.min(itemCount, perPage - skip.clamp(0, perPage - 1).toInt()),
              fill: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
              _valid
                  ? 'Each cell: ${cellW.toStringAsFixed(1)} × ${cellH.toStringAsFixed(1)} mm  ·  $perPage per page  ·  $pages page${pages == 1 ? '' : 's'}'
                  : 'No room for labels with these settings',
              style: TextStyle(color: sub, fontSize: 13)),
        ),
        if (_valid)
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              widget.onResizeLabel(
                  double.parse(cellW.toStringAsFixed(1)), double.parse(cellH.toStringAsFixed(1)));
              showInfo(context,
                  'Label size set to ${cellW.toStringAsFixed(1)} × ${cellH.toStringAsFixed(1)} mm so your design fills each cell exactly.');
            },
            child: const Text('Set label size to match one cell'),
          ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: AppColors.surface(context), borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            stepper('Skip first cells', skip, 0, math.max(0, perPage - 1),
                (v) => _set(() => skip = v)),
            if (hasData)
              stepper('Copies of each label', copies, 1, 99, (v) => _set(() => copies = v))
            else ...[
              Row(children: [
                Expanded(child: Text('Fill the page with this label', style: TextStyle(color: text))),
                CupertinoSwitch(value: fillPage, onChanged: (v) => _set(() => fillPage = v)),
              ]),
              if (!fillPage) stepper('Copies', copies, 1, 999, (v) => _set(() => copies = v)),
            ],
            Row(children: [
              Expanded(child: Text('Keep label proportions', style: TextStyle(color: text))),
              CupertinoSwitch(value: fit, onChanged: (v) => _set(() => fit = v)),
            ]),
            Row(children: [
              Expanded(child: Text('Draw cut lines', style: TextStyle(color: text))),
              CupertinoSwitch(value: cutLines, onChanged: (v) => _set(() => cutLines = v)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        CupertinoButton.filled(
          borderRadius: BorderRadius.circular(14),
          onPressed: _valid ? _print : null,
          child: const Text('Print / Preview', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 10),
        CupertinoButton(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(14),
          onPressed: _valid ? _share : null,
          child: const Text('Save / Share PDF'),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  final double pageW, pageH, margin, gap;
  final int cols, rows, skip, used;
  final Color fill;
  _GridPainter({
    required this.pageW, required this.pageH, required this.margin, required this.gap,
    required this.cols, required this.rows, required this.skip, required this.used,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sc = math.min((size.width - 16) / pageW, (size.height - 16) / pageH);
    final ox = (size.width - pageW * sc) / 2, oy = (size.height - pageH * sc) / 2;
    canvas.drawRect(Rect.fromLTWH(ox, oy, pageW * sc, pageH * sc),
        Paint()..color = const Color(0xFFFFFFFF));
    final cw = (pageW - 2 * margin - (cols - 1) * gap) / cols;
    final ch = (pageH - 2 * margin - (rows - 1) * gap) / rows;
    if (cw <= 0 || ch <= 0) return;
    for (var s = 0; s < cols * rows; s++) {
      final x = margin + (s % cols) * (cw + gap), y = margin + (s ~/ cols) * (ch + gap);
      final r = Rect.fromLTWH(ox + x * sc, oy + y * sc, cw * sc, ch * sc).deflate(0.5);
      final isUsed = s >= skip && s - skip < used;
      canvas.drawRect(r, Paint()..color = isUsed ? fill.withOpacity(0.35) : const Color(0x11000000));
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6
            ..color = const Color(0x66000000));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
