import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'native_printer.dart';
import 'store.dart';

/// Languages: escpos | tspl | cpcl | zpl.  Transports: Bluetooth, BLE, USB.
class PrinterService {
  PrinterService._();
  static final instance = PrinterService._();

  static const languages = {
    'escpos': 'ESC/POS',
    'tspl': 'TSPL',
    'cpcl': 'CPCL',
    'zpl': 'ZPL',
  };

  final connected = ValueNotifier<PrinterDevice?>(null);

  Future<bool> ensurePermissions() async {
    final res = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
    return res[Permission.bluetoothConnect]?.isGranted ?? false;
  }

  /// Paired Bluetooth + attached USB devices.
  Future<List<PrinterDevice>> knownDevices() async {
    final out = <PrinterDevice>[];
    if (await ensurePermissions()) out.addAll(await NativePrinter.bonded());
    out.addAll(await NativePrinter.usb());
    return out;
  }

  Future<List<PrinterDevice>> scanBle() async {
    if (!await ensurePermissions()) return [];
    final r = await NativePrinter.scanBle();
    r.sort((a, b) => (a.name == 'Unnamed BLE' ? 1 : 0).compareTo(b.name == 'Unnamed BLE' ? 1 : 0));
    return r;
  }

  Future<bool> connect(PrinterDevice d) async {
    try {
      final ok = await NativePrinter.connect(d);
      if (ok) {
        connected.value = d;
        await Store.saveLastPrinter(d.id, d.name, d.type);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    await NativePrinter.disconnect();
    connected.value = null;
  }

  Future<void> autoReconnect() async {
    final id = Store.lastPrinterMac;
    if (id == null) return;
    try {
      if (Store.lastPrinterType != 'usb' && !await Permission.bluetoothConnect.isGranted) return;
      await connect(PrinterDevice(Store.lastPrinterName ?? 'Printer', id, Store.lastPrinterType));
    } catch (_) {}
  }

  Future<bool> isConnected() async {
    final s = await NativePrinter.isConnected();
    if (!s) connected.value = null;
    return s;
  }

  int _dots(double mm) => (mm * Store.dpi / 25.4).round();

  Future<bool> printLabel(Uint8List png,
      {required double wMm, required double hMm, int copies = 1}) async {
    if (!await isConnected()) return false;
    var decoded = img.decodeImage(png);
    if (decoded == null) return false;
    final rot = Store.rotation;
    if (rot != 0) {
      decoded = img.copyRotate(decoded, angle: rot);
      if (rot == 90 || rot == 270) {
        final t = wMm;
        wMm = hMm;
        hMm = t;
      }
    }

    if (Store.lang == 'escpos') {
      final targetW = math.min(_dots(wMm), Store.paperDots);
      final resized = img.copyResize(decoded, width: targetW, interpolation: img.Interpolation.average);
      final profile = await CapabilityProfile.load();
      final gen = Generator(Store.paperDots == 576 ? PaperSize.mm80 : PaperSize.mm58, profile);
      final bytes = <int>[...gen.reset()];
      for (var i = 0; i < copies; i++) {
        bytes.addAll(gen.imageRaster(resized, align: PosAlign.center));
        bytes.addAll(gen.feed(1));
      }
      return NativePrinter.write(bytes);
    }

    final fitted = img.copyResize(decoded,
        width: _dots(wMm), height: _dots(hMm), interpolation: img.Interpolation.average);
    return NativePrinter.write(_build(Store.lang, fitted, wMm, hMm, copies));
  }

  Future<bool> printQuick(Uint8List png, {int copies = 1}) async {
    if (Store.lang == 'escpos') {
      return printLabel(png, wMm: Store.paperDots * 25.4 / Store.dpi, hMm: 0, copies: copies);
    }
    if (!await isConnected()) return false;
    final src = img.decodeImage(png);
    if (src == null) return false;
    final w = Store.quickW, h = Store.quickH;
    final dw = _dots(w), dh = _dots(h);
    final canvas = img.Image(width: dw, height: dh);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    final scale = math.min(dw * 0.92 / src.width, dh * 0.92 / src.height);
    final r = img.copyResize(src, width: (src.width * scale).round());
    img.compositeImage(canvas, r, dstX: (dw - r.width) ~/ 2, dstY: (dh - r.height) ~/ 2);
    final rot = Store.rotation;
    if (rot == 0) return NativePrinter.write(_build(Store.lang, canvas, w, h, copies));
    final rc = img.copyRotate(canvas, angle: rot);
    final swap = rot == 90 || rot == 270;
    return NativePrinter.write(_build(Store.lang, rc, swap ? h : w, swap ? w : h, copies));
  }

  // ---------- language builders ----------
  ({int bpr, Uint8List data}) _pack(img.Image im, {required bool blackIsOne}) {
    final w = im.width, h = im.height;
    final bpr = (w + 7) ~/ 8;
    final data = Uint8List(bpr * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < bpr * 8; x++) {
        var black = false; // padding = white
        if (x < w) {
          final p = im.getPixel(x, y);
          black = (p.r * 0.299 + p.g * 0.587 + p.b * 0.114) < 128;
        }
        final setBit = blackIsOne ? black : !black;
        if (setBit) data[y * bpr + (x >> 3)] |= (1 << (7 - (x & 7)));
      }
    }
    return (bpr: bpr, data: data);
  }

  List<int> _build(String lang, img.Image im, double wMm, double hMm, int copies) =>
      switch (lang) {
        'cpcl' => _cpcl(im, copies),
        'zpl' => _zpl(im, copies),
        _ => _tspl(im, wMm, hMm, copies),
      };

  List<int> _tspl(img.Image im, double wMm, double hMm, int copies) {
    final p = _pack(im, blackIsOne: false); // TSPL: 0 = black dot
    final header = 'SIZE ${wMm.toStringAsFixed(1)} mm,${hMm.toStringAsFixed(1)} mm\r\n'
        'GAP ${Store.gapMm.toStringAsFixed(1)} mm,0 mm\r\n'
        'DIRECTION 1\r\nDENSITY ${Store.density}\r\nCLS\r\n'
        'BITMAP 0,0,${p.bpr},${im.height},0,';
    return [...ascii.encode(header), ...p.data, ...ascii.encode('\r\nPRINT $copies,1\r\n')];
  }

  List<int> _cpcl(img.Image im, int copies) {
    final p = _pack(im, blackIsOne: true); // CPCL: 1 = black dot
    final d = Store.dpi;
    final head = '! 0 $d $d ${im.height} $copies\r\nPAGE-WIDTH ${im.width}\r\n'
        'CG ${p.bpr} ${im.height} 0 0 ';
    return [...ascii.encode(head), ...p.data, ...ascii.encode('\r\nFORM\r\nPRINT\r\n')];
  }

  List<int> _zpl(img.Image im, int copies) {
    final p = _pack(im, blackIsOne: true); // ZPL: 1 = black dot
    final hex = StringBuffer();
    for (final b in p.data) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    final n = p.data.length;
    final s = '^XA^PW${im.width}^LL${im.height}^PQ$copies\n'
        '^FO0,0^GFA,$n,$n,${p.bpr},${hex.toString().toUpperCase()}^FS\n^XZ\n';
    return ascii.encode(s);
  }

  // ---------- tests ----------
  List<int> _testFor(String lang) {
    switch (lang) {
      case 'tspl':
        return ascii.encode(
            'SIZE ${Store.quickW.toStringAsFixed(1)} mm,${Store.quickH.toStringAsFixed(1)} mm\r\n'
            'GAP ${Store.gapMm.toStringAsFixed(1)} mm,0 mm\r\nCLS\r\n'
            'TEXT 20,20,"3",0,1,1,"TSPL OK"\r\nPRINT 1,1\r\n');
      case 'cpcl':
        return ascii.encode(
            '! 0 200 200 240 1\r\nTEXT 4 0 20 20 CPCL OK\r\nFORM\r\nPRINT\r\n');
      case 'zpl':
        return ascii.encode('^XA^FO20,20^A0N,50,50^FDZPL OK^FS^XZ\n');
      default:
        return [
          0x1B, 0x40,
          ...ascii.encode('ESC/POS OK\n\n\n'),
        ];
    }
  }

  /// Sends a test in the selected language.
  Future<bool> printTest() async {
    if (!await isConnected()) return false;
    return NativePrinter.write(_testFor(Store.lang));
  }

  /// Sends one test per language. Whichever prints readable text is your language.
  Future<bool> printTestAll() async {
    if (!await isConnected()) return false;
    for (final l in languages.keys) {
      if (!await NativePrinter.write(_testFor(l))) return false;
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    return true;
  }
}
