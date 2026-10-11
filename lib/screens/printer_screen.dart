import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../services/native_printer.dart';
import '../services/printer_service.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets.dart';

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});
  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  final _svc = PrinterService.instance;
  List<PrinterDevice> _devices = [];
  bool _loading = false, _scanning = false;
  String? _connectingId;
  int _paper = Store.paperDots;
  String _lang = Store.lang;
  int _dpi = Store.dpi;
  double _gap = Store.gapMm;
  int _density = Store.density;
  int _rot = Store.rotation;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final list = await _svc.knownDevices();
      await _svc.isConnected();
      if (mounted) setState(() => _devices = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanBle() async {
    setState(() => _scanning = true);
    try {
      final found = await _svc.scanBle();
      if (!mounted) return;
      final known = _devices.map((e) => e.id).toSet();
      setState(() => _devices = [..._devices, ...found.where((d) => !known.contains(d.id))]);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(PrinterDevice d) async {
    HapticFeedback.selectionClick();
    setState(() => _connectingId = d.id);
    final ok = await _svc.connect(d);
    if (!mounted) return;
    setState(() => _connectingId = null);
    if (!ok) {
      showInfo(context,
          'Turn the printer on and keep it close. If it is a Bluetooth LE printer, use "Scan Bluetooth LE". For USB, use an OTG cable and allow access.',
          title: 'Could not connect');
    }
  }

  Widget _stepper(String label, String value, VoidCallback? minus, VoidCallback? plus) {
    return Row(children: [
      Expanded(child: Text('$label: $value', style: TextStyle(color: AppColors.text(context)))),
      CupertinoButton(
          padding: EdgeInsets.zero, minSize: 36, onPressed: minus,
          child: const Icon(CupertinoIcons.minus_circle)),
      CupertinoButton(
          padding: EdgeInsets.zero, minSize: 36, onPressed: plus,
          child: const Icon(CupertinoIcons.plus_circle)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppColors.text(context);
    final sub = AppColors.subtext(context);
    Widget head(String s) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(s, style: TextStyle(color: sub, fontSize: 13)));

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Printer'),
            border: null,
            trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _refresh,
                child: const Icon(CupertinoIcons.refresh)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList.list(children: [
              ValueListenableBuilder<PrinterDevice?>(
                valueListenable: _svc.connected,
                builder: (_, c, __) => AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: c != null
                          ? CupertinoColors.activeGreen.withOpacity(0.15)
                          : AppColors.surface(context),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    Icon(
                        c != null
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.bluetooth,
                        color: c != null ? CupertinoColors.activeGreen : sub),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          c != null
                              ? 'Connected: ${c.name} (${c.typeLabel})'
                              : 'No printer connected',
                          style: TextStyle(color: text, fontWeight: FontWeight.w600)),
                    ),
                    if (c != null)
                      CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: _svc.disconnect,
                          child: const Text('Disconnect')),
                  ]),
                ),
              ),

              head('PRINTER LANGUAGE'),
              segmented<String>(context, _lang, PrinterService.languages, (v) {
                setState(() => _lang = v);
                Store.setLang(v);
              }),
              const SizedBox(height: 4),
              Text(
                  'Not sure? Connect, tap "Test all languages", and pick the one that printed readable text.',
                  style: TextStyle(color: sub, fontSize: 12)),

              head('RESOLUTION'),
              segmented<int>(context, _dpi, {203: '203 dpi', 300: '300 dpi'}, (v) {
                setState(() => _dpi = v);
                Store.setDpi(v);
              }),

              head('PRINT ROTATION'),
              segmented<int>(context, _rot, {0: '0°', 90: '90°', 180: '180°', 270: '270°'}, (v) {
                setState(() => _rot = v);
                Store.setRotation(v);
              }),

              if (_lang == 'escpos') ...[
                head('PAPER WIDTH'),
                segmented<int>(context, _paper, {384: '58 mm', 576: '80 mm'}, (v) {
                  setState(() => _paper = v);
                  Store.setPaperDots(v);
                }),
              ] else ...[
                head('LABEL SETTINGS'),
                _stepper(
                    'Gap',
                    _gap == 0 ? 'continuous' : '${_gap.toStringAsFixed(1)} mm',
                    _gap > 0
                        ? () {
                            setState(() => _gap = (_gap - 0.5).clamp(0, 10).toDouble());
                            Store.setGapMm(_gap);
                          }
                        : null, () {
                  setState(() => _gap = (_gap + 0.5).clamp(0, 10).toDouble());
                  Store.setGapMm(_gap);
                }),
                if (_lang == 'tspl')
                  _stepper(
                      'Darkness',
                      '$_density',
                      _density > 0
                          ? () {
                              setState(() => _density--);
                              Store.setDensity(_density);
                            }
                          : null,
                      _density < 15
                          ? () {
                              setState(() => _density++);
                              Store.setDensity(_density);
                            }
                          : null),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    final r = await pickLabelSize(context);
                    if (r != null) {
                      await Store.setQuickSize(r.$1, r.$2);
                      setState(() {});
                    }
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'Quick Code label size: ${Store.quickW.toStringAsFixed(0)} × ${Store.quickH.toStringAsFixed(0)} mm'),
                  ),
                ),
              ],

              head('DEVICES'),
              if (_loading)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CupertinoActivityIndicator()))
              else if (_devices.isEmpty)
                Text(
                    'No devices found. Pair classic Bluetooth printers in Android Settings first, '
                    'plug USB printers in with an OTG cable, or scan for Bluetooth LE printers below.',
                    style: TextStyle(color: sub))
              else
                for (final d in _devices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () => _connect(d),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: AppColors.surface(context),
                            borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d.name,
                                      style: TextStyle(
                                          color: text, fontWeight: FontWeight.w600)),
                                  Text('${d.typeLabel}  ·  ${d.id}',
                                      style: TextStyle(color: sub, fontSize: 12)),
                                ]),
                          ),
                          if (_connectingId == d.id)
                            const CupertinoActivityIndicator()
                          else
                            const Icon(CupertinoIcons.chevron_forward,
                                size: 16, color: CupertinoColors.systemGrey),
                        ]),
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              CupertinoButton(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(14),
                onPressed: _scanning ? null : _scanBle,
                child: _scanning
                    ? const CupertinoActivityIndicator()
                    : const Text('Scan Bluetooth LE'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: CupertinoButton(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    onPressed: () async {
                      final ok = await _svc.printTest();
                      if (mounted) {
                        showInfo(context, ok ? 'Test sent' : 'Connect a printer first');
                      }
                    },
                    child: const Text('Print test', style: TextStyle(fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CupertinoButton(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    onPressed: () async {
                      final ok = await _svc.printTestAll();
                      if (mounted) {
                        showInfo(
                            context,
                            ok
                                ? 'Sent 4 tests: ESC/POS, TSPL, CPCL, ZPL. Choose the language whose test printed readable text.'
                                : 'Connect a printer first');
                      }
                    },
                    child: const Text('Test all languages', style: TextStyle(fontSize: 15)),
                  ),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}
