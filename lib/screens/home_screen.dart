import 'dart:io';
import 'dart:ui' as ui;
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/printer_service.dart';
import '../services/store.dart';
import '../theme.dart';
import '../main.dart' show tabController;

enum CodeType {
  code128('128', 'Code 128', 'HELLO-12345'),
  ean13('EAN-13', 'EAN-13', '590123412345'),
  upcA('UPC-A', 'UPC-A', '03600029145'),
  code39('39', 'Code 39', 'CODE39'),
  qr('QR', 'QR Code', 'https://example.com');

  final String short, label, sample;
  const CodeType(this.short, this.label, this.sample);

  Barcode get barcode => switch (this) {
        CodeType.code128 => Barcode.code128(),
        CodeType.ean13 => Barcode.ean13(),
        CodeType.upcA => Barcode.upcA(),
        CodeType.code39 => Barcode.code39(),
        CodeType.qr => Barcode.qrCode(),
      };

  String get hint => switch (this) {
        CodeType.code128 => 'Any text or numbers',
        CodeType.ean13 => '12 or 13 digits',
        CodeType.upcA => '11 or 12 digits',
        CodeType.code39 => 'A–Z, 0–9 and - . \$ / + % space',
        CodeType.qr => 'Text, link, Wi-Fi, anything',
      };
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _key = GlobalKey();
  final _ctrl = TextEditingController(text: CodeType.code128.sample);
  CodeType _type = CodeType.code128;
  bool _showText = true;
  int _copies = 1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Store.loadRequest.addListener(_onLoadRequest);
  }

  @override
  void dispose() {
    Store.loadRequest.removeListener(_onLoadRequest);
    _ctrl.dispose();
    super.dispose();
  }

  void _onLoadRequest() {
    final r = Store.loadRequest.value;
    if (r == null) return;
    setState(() {
      _type = CodeType.values.firstWhere((t) => t.name == r.type);
      _ctrl.text = r.data;
    });
    Store.loadRequest.value = null;
  }

  bool get _valid => _ctrl.text.isNotEmpty && _type.barcode.isValid(_ctrl.text);

  Future<Uint8List?> _capture() async {
    final b = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (b == null) return null;
    final image = await b.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  void _toast(String msg) {
    showCupertinoDialog(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        content: Text(msg),
        actions: [
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(c),
              child: const Text('OK'))
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_valid) return;
    HapticFeedback.mediumImpact();
    await Store.add(_type.name, _ctrl.text);
    if (mounted) _toast('Saved to History');
  }

  Future<void> _share() async {
    if (!_valid) return;
    HapticFeedback.selectionClick();
    final png = await _capture();
    if (png == null) return;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/barcode_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(png);
    await Share.shareXFiles([XFile(f.path)]);
  }

  Future<void> _print() async {
    if (!_valid || _busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      final svc = PrinterService.instance;
      if (!await svc.isConnected()) {
        if (!mounted) return;
        _toast('No printer connected. Open the Printer tab to connect one.');
        tabController.index = 3;
        return;
      }
      final png = await _capture();
      if (png == null) return;
      final ok = await svc.printQuick(png, copies: _copies);
      await Store.add(_type.name, _ctrl.text);
      if (mounted) _toast(ok ? 'Sent to printer' : 'Printing failed. Check the printer.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppColors.text(context);
    final sub = AppColors.subtext(context);
    final isQr = _type == CodeType.qr;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('Quick Code'),
            border: null,
          ),
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList.list(children: [
                // Type picker
                SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<CodeType>(
                    groupValue: _type,
                    thumbColor: AppColors.isDark(context)
                        ? const Color(0xFF3A3A3C)
                        : CupertinoColors.white,
                    children: {
                      for (final t in CodeType.values)
                        t: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(t.short,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: text)),
                        )
                    },
                    onValueChanged: (t) {
                      if (t == null) return;
                      HapticFeedback.selectionClick();
                      setState(() {
                        _type = t;
                        _ctrl.text = t.sample;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(_type.label,
                      style: TextStyle(color: sub, fontSize: 13)),
                ),
                const SizedBox(height: 16),

                // Preview card (white always, so scanners read it in dark mode)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: AppColors.isDark(context)
                            ? const Color(0x33FFFFFF)
                            : const Color(0x1A000000)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RepaintBoundary(
                    key: _key,
                    child: Container(
                      color: CupertinoColors.white,
                      padding: const EdgeInsets.all(24),
                      width: double.infinity,
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 380),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(
                                scale: Tween(begin: 0.92, end: 1.0).animate(anim),
                                child: child),
                          ),
                          child: _valid
                              ? BarcodeWidget(
                                  key: ValueKey(_type),
                                  barcode: _type.barcode,
                                  data: _ctrl.text,
                                  width: isQr ? 200 : double.infinity,
                                  height: isQr ? 200 : 110,
                                  drawText: _showText && !isQr,
                                  color: CupertinoColors.black,
                                  backgroundColor: CupertinoColors.white,
                                  style: const TextStyle(
                                      color: CupertinoColors.black, fontSize: 14),
                                )
                              : SizedBox(
                                  key: const ValueKey('invalid'),
                                  height: 110,
                                  child: Center(
                                    child: Text(
                                      _ctrl.text.isEmpty
                                          ? 'Type something to begin'
                                          : 'Not valid for ${_type.label}\n${_type.hint}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Color(0x99000000), fontSize: 15),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                CupertinoTextField(
                  controller: _ctrl,
                  placeholder: _type.hint,
                  onChanged: (_) => setState(() {}),
                  padding: const EdgeInsets.all(14),
                  clearButtonMode: OverlayVisibilityMode.editing,
                  style: TextStyle(color: text, fontSize: 17),
                  placeholderStyle: TextStyle(color: sub, fontSize: 17),
                  decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(12)),
                ),
                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                          child: Text('Show text under bars',
                              style: TextStyle(color: text))),
                      CupertinoSwitch(
                          value: _showText,
                          onChanged: isQr
                              ? null
                              : (v) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _showText = v);
                                }),
                    ]),
                    Container(height: 0.5, color: sub.withOpacity(0.3)),
                    Row(children: [
                      Expanded(
                          child: Text('Copies: $_copies',
                              style: TextStyle(color: text))),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 36,
                        onPressed: _copies > 1
                            ? () => setState(() => _copies--)
                            : null,
                        child: const Icon(CupertinoIcons.minus_circle),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 36,
                        onPressed: _copies < 20
                            ? () => setState(() => _copies++)
                            : null,
                        child: const Icon(CupertinoIcons.plus_circle),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(height: 20),

                CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _valid && !_busy ? _print : null,
                  child: _busy
                      ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                      : const Text('Print Label',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: CupertinoButton(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(14),
                      onPressed: _valid ? _save : null,
                      child: const Text('Save'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CupertinoButton(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(14),
                      onPressed: _valid ? _share : null,
                      child: const Text('Share PNG'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
