import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:barcode/barcode.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models.dart';
import '../services/printer_service.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'data_panel.dart';
import 'home_screen.dart' show CodeType;
import 'sheet_panel.dart';

class EditorScreen extends StatefulWidget {
  final LabelTemplate template; // working copy
  const EditorScreen({super.key, required this.template});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late LabelTemplate t = widget.template;
  final _boundaryKey = GlobalKey();
  String? _selId;
  bool _dirty = false;
  bool _busy = false;
  int _copies = 1;
  final _dataCtrl = TextEditingController();
  final _imgCache = <String, Uint8List>{};

  // data rows (serial range / custom list / excel)
  List<List<String>> _rows = [];
  int _row = 0;

  LabelElement? get _sel => t.elements.where((e) => e.id == _selId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _refreshRows();
  }

  @override
  void dispose() {
    _dataCtrl.dispose();
    if (_dirty) Future.microtask(() => Store.saveTemplate(t)); // autosave
    super.dispose();
  }

  void _refreshRows() {
    _rows = t.generateRows();
    if (_row >= _rows.length) _row = math.max(0, _rows.length - 1);
  }

  void _edit(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  void _select(String? id) {
    if (_selId == id) return;
    setState(() {
      _selId = id;
      _dataCtrl.text = _sel?.data ?? '';
    });
  }

  void _add(String kind) {
    HapticFeedback.mediumImpact();
    final e = switch (kind) {
      'text' => LabelElement(id: newId(), kind: kind, data: 'Text', x: 3, y: 3, w: math.min(30, t.wMm - 4), h: 7, fontSize: 4.5),
      'barcode' => LabelElement(id: newId(), kind: kind, data: CodeType.code128.sample, x: 3, y: 3, w: math.min(36, t.wMm - 4), h: 12),
      'line' => LabelElement(id: newId(), kind: kind, data: '', x: 3, y: 3, w: math.min(30, t.wMm - 4), h: 0.6),
      'box' => LabelElement(id: newId(), kind: kind, data: '', x: 3, y: 3, w: math.min(20, t.wMm - 4), h: math.min(10, t.hMm - 4)),
      _ => LabelElement(id: newId(), kind: kind, data: 'https://example.com', x: 3, y: 3, w: math.min(16, t.hMm - 2), h: math.min(16, t.hMm - 2)),
    };
    _edit(() => t.elements.add(e));
    _select(e.id);
  }

  Future<void> _addImage() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    final e = LabelElement(
        id: newId(), kind: 'image', data: base64Encode(bytes),
        x: 3, y: 3, w: math.min(20, t.wMm - 4), h: math.min(20, t.hMm - 4));
    _edit(() => t.elements.add(e));
    _select(e.id);
  }

  Future<Uint8List?> _capture({int? dpi}) async {
    final b = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (b == null) return null;
    final dotsW = t.wMm * (dpi ?? Store.dpi) / 25.4;
    final image = await b.toImage(pixelRatio: dotsW / b.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  /// Shows data row [i] on the canvas, waits for the frame, and captures it.
  Future<Uint8List?> _renderRow(int i, {int? dpi}) async {
    if (_rows.isNotEmpty) {
      setState(() => _row = i.clamp(0, _rows.length - 1).toInt());
      await WidgetsBinding.instance.endOfFrame;
    }
    return _capture(dpi: dpi);
  }

  Future<void> _print() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    final svc = PrinterService.instance;
    if (!await svc.isConnected()) {
      if (mounted) {
        showInfo(context, 'Go to the Printer tab, connect your printer, then come back.',
            title: 'No printer connected');
      }
      return;
    }
    final total = _rows.isEmpty ? 1 : _rows.length;
    if (total > 1 &&
        !await confirmDialog(context,
            'Print $total labels${_copies > 1 ? ', $_copies copies of each' : ''}?')) {
      return;
    }
    setState(() => _busy = true);
    final prev = _row;
    try {
      if (_rows.isEmpty) {
        final png = await _capture();
        if (png == null) return;
        final ok = await svc.printLabel(png, wMm: t.wMm, hMm: t.hMm, copies: _copies);
        if (mounted) showInfo(context, ok ? 'Sent to printer.' : 'Printing failed. Check the printer.');
      } else {
        var done = 0;
        var failed = false;
        await runWithProgress(context, 'Printing labels', total, (report, cancelled) async {
          for (var i = 0; i < total; i++) {
            if (cancelled()) break;
            final png = await _renderRow(i);
            if (png == null) continue;
            final ok = await svc.printLabel(png, wMm: t.wMm, hMm: t.hMm, copies: _copies);
            if (!ok) {
              failed = true;
              break;
            }
            done = i + 1;
            report(done);
            await Future.delayed(const Duration(milliseconds: 150));
          }
        });
        if (mounted) {
          showInfo(context,
              failed ? 'Stopped after $done label(s). Check the printer.' : 'Printed $done of $total labels.');
        }
      }
    } finally {
      if (mounted) setState(() {
            _row = prev;
            _busy = false;
          });
    }
  }

  Future<void> _save() async {
    await Store.saveTemplate(t);
    _dirty = false;
    HapticFeedback.mediumImpact();
    if (mounted) showInfo(context, 'Template saved.');
  }

  Future<void> _rename() async {
    final n = await askText(context, 'Template name', t.name);
    if (n != null && n.isNotEmpty) _edit(() => t.name = n);
  }

  Future<void> _resize() async {
    final s = await pickLabelSize(context, initial: (t.wMm, t.hMm));
    if (s != null) _edit(() {
          t.wMm = s.$1;
          t.hMm = s.$2;
        });
  }

  void _openData() {
    showSheet(context, 'Numbers & data',
        (c) => DataPanel(
              t: t,
              onChanged: () => setState(() {
                _dirty = true;
                _refreshRows();
              }),
            ));
  }

  void _openSheet() {
    showSheet(
        context,
        'Sheet layout',
        (c) => SheetPanel(
              t: t,
              labelCount: _rows.length,
              render: (i, dpi) => _renderRow(i, dpi: dpi),
              onResizeLabel: (w, h) => _edit(() {
                t.wMm = w;
                t.hMm = h;
              }),
            ));
  }

  // ---------------- rendering ----------------
  String _expand(String s) {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    var out = s
        .replaceAll('{date}', '${n.year}-${two(n.month)}-${two(n.day)}')
        .replaceAll('{time}', '${two(n.hour)}:${two(n.minute)}');
    final r = _rows.isEmpty ? const ['1'] : _rows[_row.clamp(0, _rows.length - 1).toInt()];
    out = out.replaceAll('{n}', r.isNotEmpty ? r[0] : '');
    for (var i = 0; i < r.length && i < 30; i++) {
      out = out.replaceAll('{${i + 1}}', r[i]);
    }
    return out;
  }

  Widget _render(LabelElement e, double ppm) {
    const black = CupertinoColors.black;
    switch (e.kind) {
      case 'text':
        return SizedBox(
          width: e.w * ppm,
          height: e.h * ppm,
          child: ClipRect(
            child: Text(_expand(e.data),
                style: TextStyle(
                    inherit: false,
                    color: black,
                    fontSize: e.fontSize * ppm,
                    height: 1.1,
                    fontWeight: e.bold ? FontWeight.w800 : FontWeight.w400,
                    fontFamily: '.SF Pro Text',
                    decoration: TextDecoration.none)),
          ),
        );
      case 'image':
        final bytes = _imgCache.putIfAbsent(e.id, () => base64Decode(e.data));
        return SizedBox(
            width: e.w * ppm,
            height: e.h * ppm,
            child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true));
      case 'line':
        return Container(width: e.w * ppm, height: math.max(1.0, e.h * ppm), color: black);
      case 'box':
        return Container(
            width: e.w * ppm,
            height: e.h * ppm,
            decoration: BoxDecoration(
                border: Border.all(color: black, width: math.max(1.0, 0.5 * ppm))));
      case 'qr':
        final d = _expand(e.data);
        return BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: d.isEmpty ? ' ' : d,
            width: e.w * ppm,
            height: e.h * ppm,
            color: black,
            backgroundColor: CupertinoColors.white,
            errorBuilder: (c, err) => const SizedBox());
      default:
        final type = CodeType.values.firstWhere((c) => c.name == e.codeType,
            orElse: () => CodeType.code128);
        final hpx = e.h * ppm;
        final fs = e.numFontSize > 0
            ? math.min(e.numFontSize * ppm, hpx * 0.6)
            : math.max(6.0, hpx * 0.2);
        return BarcodeWidget(
            barcode: type.barcode,
            data: _expand(e.data),
            width: e.w * ppm,
            height: hpx,
            drawText: e.showText,
            color: black,
            backgroundColor: CupertinoColors.white,
            style: TextStyle(
                color: black, fontSize: fs, decoration: TextDecoration.none),
            errorBuilder: (c, err) => SizedBox(
                width: e.w * ppm,
                height: hpx,
                child: const Center(
                    child: Text('invalid data',
                        style: TextStyle(
                            fontSize: 9,
                            color: CupertinoColors.destructiveRed,
                            decoration: TextDecoration.none)))));
    }
  }

  Widget _canvas() {
    return LayoutBuilder(builder: (context, box) {
      final ppm = math.min((box.maxWidth - 32) / t.wMm, (box.maxHeight - 32) / t.hMm);
      final cw = t.wMm * ppm, ch = t.hMm * ppm;
      final ordered = [
        ...t.elements.where((e) => e.id != _selId),
        ...t.elements.where((e) => e.id == _selId),
      ];
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(null),
        child: Container(
          color: AppColors.surface(context),
          alignment: Alignment.center,
          child: Container(
            width: cw,
            height: ch,
            decoration: const BoxDecoration(color: CupertinoColors.white, boxShadow: [
              BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))
            ]),
            child: Stack(children: [
              // This layer is what gets printed (no selection chrome in it)
              RepaintBoundary(
                key: _boundaryKey,
                child: Container(
                  width: cw,
                  height: ch,
                  color: CupertinoColors.white,
                  child: Stack(clipBehavior: Clip.hardEdge, children: [
                    for (final e in t.elements)
                      Positioned(left: e.x * ppm, top: e.y * ppm, child: _render(e, ppm)),
                  ]),
                ),
              ),
              // Touch layer
              for (final e in ordered)
                Positioned(
                  left: e.x * ppm,
                  top: e.y * ppm,
                  width: math.max(e.w * ppm, 24.0),
                  height: math.max(e.h * ppm, 24.0),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _select(e.id),
                    onPanStart: (_) => _select(e.id),
                    onPanUpdate: (d) => _edit(() {
                      e.x = (e.x + d.delta.dx / ppm).clamp(0.0, math.max(0.0, t.wMm - e.w)).toDouble();
                      e.y = (e.y + d.delta.dy / ppm).clamp(0.0, math.max(0.0, t.hMm - e.h)).toDouble();
                    }),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: e.id == _selId
                                  ? AppColors.accent
                                  : const Color(0x22808080),
                              width: e.id == _selId ? 1.6 : 0.6)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> on) {
    return Row(children: [
      SizedBox(
          width: 86,
          child: Text(label,
              style: TextStyle(fontSize: 14, color: AppColors.text(context)))),
      Expanded(
          child: CupertinoSlider(
              value: v.clamp(min, max).toDouble(), min: min, max: max, onChanged: on)),
      SizedBox(
          width: 40,
          child: Text(v.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: AppColors.subtext(context)))),
    ]);
  }

  Widget _inspector(LabelElement e) {
    final text = AppColors.text(context);
    final isShape = e.kind == 'line' || e.kind == 'box' || e.kind == 'image';
    final isQr = e.kind == 'qr';
    return Column(children: [
      if (!isShape)
        CupertinoTextField(
          controller: _dataCtrl,
          maxLines: e.kind == 'text' ? 3 : 1,
          minLines: 1,
          placeholder: e.kind == 'text'
              ? 'Text  ({n} number, {date}, {time})'
              : 'Content  (use {n} for numbers)',
          padding: const EdgeInsets.all(12),
          style: TextStyle(color: text),
          placeholderStyle: TextStyle(color: AppColors.subtext(context)),
          decoration: BoxDecoration(
              color: AppColors.surface(context), borderRadius: BorderRadius.circular(10)),
          onChanged: (v) => _edit(() => e.data = v),
        ),
      const SizedBox(height: 10),
      if (e.kind == 'barcode') ...[
        segmented<String>(context, e.codeType, {
          for (final c in CodeType.values.where((c) => c != CodeType.qr)) c.name: c.short
        }, (v) {
          final c = CodeType.values.firstWhere((x) => x.name == v);
          _edit(() {
            e.codeType = v;
            if (!c.barcode.isValid(_expand(e.data))) e.data = c.sample;
          });
          _dataCtrl.text = e.data;
        }),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('Show numbers below', style: TextStyle(color: text))),
          CupertinoSwitch(value: e.showText, onChanged: (v) => _edit(() => e.showText = v)),
        ]),
        if (e.showText)
          _slider('Number size', e.numFontSize > 0 ? e.numFontSize : math.max(1.5, e.h * 0.2),
              1, 14, (v) => _edit(() => e.numFontSize = v)),
      ],
      if (e.kind == 'text') ...[
        _slider('Font size', e.fontSize, 2, 30, (v) => _edit(() => e.fontSize = v)),
        Row(children: [
          Expanded(child: Text('Bold', style: TextStyle(color: text))),
          CupertinoSwitch(value: e.bold, onChanged: (v) => _edit(() => e.bold = v)),
        ]),
      ],
      const SizedBox(height: 4),
      // exact numbers (mm)
      Row(children: [
        Expanded(
            child: NumBox(
                label: 'X mm',
                value: e.x,
                onChanged: (v) => _edit(() => e.x = v.clamp(0, t.wMm).toDouble()))),
        const SizedBox(width: 8),
        Expanded(
            child: NumBox(
                label: 'Y mm',
                value: e.y,
                onChanged: (v) => _edit(() => e.y = v.clamp(0, t.hMm).toDouble()))),
        const SizedBox(width: 8),
        Expanded(
            child: NumBox(
                label: 'Width mm',
                value: e.w,
                onChanged: (v) => _edit(() {
                      e.w = v.clamp(1, t.wMm).toDouble();
                      if (isQr) e.h = e.w;
                    }))),
        const SizedBox(width: 8),
        Expanded(
            child: NumBox(
                label: 'Height mm',
                value: e.h,
                onChanged: (v) => _edit(() {
                      e.h = v.clamp(e.kind == 'line' ? 0.2 : 1, t.hMm).toDouble();
                      if (isQr) e.w = e.h;
                    }))),
      ]),
      const SizedBox(height: 4),
      if (isQr)
        _slider('Size', e.w, 5, math.min(t.wMm, t.hMm), (v) => _edit(() {
              e.w = v;
              e.h = v;
            }))
      else ...[
        _slider('Width', e.w, 3, t.wMm, (v) => _edit(() => e.w = v)),
        _slider('Height', e.h, e.kind == 'line' ? 0.3 : 3, t.hMm, (v) => _edit(() => e.h = v)),
      ],
      Align(
        alignment: Alignment.centerRight,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            HapticFeedback.mediumImpact();
            _edit(() => t.elements.removeWhere((x) => x.id == e.id));
            _select(null);
          },
          child: const Text('Delete element',
              style: TextStyle(color: CupertinoColors.destructiveRed)),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final sel = _sel;
    final maxPanel = MediaQuery.sizeOf(context).height * 0.5;
    Widget btn(String label, IconData icon, VoidCallback on) => Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(12),
            onPressed: on,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 14)),
            ]),
          ),
        );
    Widget addBtn(String label, IconData icon, String kind) => btn(label, icon, () => _add(kind));

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        backgroundColor: AppColors.bg(context).withOpacity(0.9),
        middle: GestureDetector(
            onTap: _rename,
            child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _resize,
              child: Text('${t.wMm.toStringAsFixed(t.wMm % 1 == 0 ? 0 : 1)}×${t.hMm.toStringAsFixed(t.hMm % 1 == 0 ? 0 : 1)}',
                  style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 12),
          CupertinoButton(
              padding: EdgeInsets.zero, onPressed: _save, child: const Text('Save')),
        ]),
      ),
      child: SafeArea(
        child: Column(children: [
          Expanded(child: _canvas()),
          if (_rows.isNotEmpty)
            Container(
              color: AppColors.bg(context),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 34,
                    onPressed: _row > 0 ? () => setState(() => _row--) : null,
                    child: const Icon(CupertinoIcons.chevron_left)),
                Expanded(
                    child: Center(
                        child: Text('Previewing label ${_row + 1} of ${_rows.length}',
                            style: TextStyle(fontSize: 13, color: AppColors.subtext(context))))),
                CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 34,
                    onPressed: _row < _rows.length - 1 ? () => setState(() => _row++) : null,
                    child: const Icon(CupertinoIcons.chevron_right)),
              ]),
            ),
          Container(
            constraints: BoxConstraints(maxHeight: maxPanel),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            decoration: BoxDecoration(
                color: AppColors.bg(context),
                border: Border(
                    top: BorderSide(color: AppColors.subtext(context).withOpacity(0.2)))),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(children: [
                Row(children: [
                  addBtn('Text', CupertinoIcons.textformat, 'text'),
                  const SizedBox(width: 8),
                  addBtn('Barcode', CupertinoIcons.barcode, 'barcode'),
                  const SizedBox(width: 8),
                  addBtn('QR', CupertinoIcons.qrcode, 'qr'),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  addBtn('Line', CupertinoIcons.minus, 'line'),
                  const SizedBox(width: 8),
                  addBtn('Box', CupertinoIcons.square, 'box'),
                  const SizedBox(width: 8),
                  btn('Image', CupertinoIcons.photo, _addImage),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  btn(_rows.isEmpty ? 'Numbers / Excel' : '${_rows.length} labels',
                      CupertinoIcons.list_number, _openData),
                  const SizedBox(width: 8),
                  btn('A4 Sheet', CupertinoIcons.doc_on_doc, _openSheet),
                ]),
                AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: sel == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text('Tap an element to edit it. Drag to move.',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.subtext(context))))
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _inspector(sel)),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Text('Copies: $_copies',
                      style: TextStyle(color: AppColors.text(context))),
                  CupertinoButton(
                      padding: const EdgeInsets.only(left: 8),
                      minSize: 32,
                      onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                      child: const Icon(CupertinoIcons.minus_circle)),
                  CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 32,
                      onPressed: _copies < 99 ? () => setState(() => _copies++) : null,
                      child: const Icon(CupertinoIcons.plus_circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      borderRadius: BorderRadius.circular(14),
                      onPressed: _busy ? null : _print,
                      child: _busy
                          ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                          : Text(_rows.length > 1 ? 'Print ${_rows.length}' : 'Print',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
