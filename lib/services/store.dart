import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';

class HistoryItem {
  final String type; // CodeType.name
  final String data;
  final int ts;
  HistoryItem(this.type, this.data, this.ts);
  Map<String, dynamic> toJson() => {'t': type, 'd': data, 'ts': ts};
  factory HistoryItem.fromJson(Map<String, dynamic> j) =>
      HistoryItem(j['t'], j['d'], j['ts']);
}

/// Everything is stored on-device. The app never touches the network.
class Store {
  static late SharedPreferences _p;
  static final history = ValueNotifier<List<HistoryItem>>([]);
  /// Set by History tab; Create tab loads it.
  static final loadRequest = ValueNotifier<HistoryItem?>(null);

  static final templates = ValueNotifier<List<LabelTemplate>>([]);

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    final t = _p.getString('templates');
    if (t != null) {
      templates.value = (jsonDecode(t) as List)
          .map((e) => LabelTemplate.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      templates.value = [_sample()];
      await _persistTemplates();
    }
    final raw = _p.getString('history');
    if (raw != null) {
      history.value = (jsonDecode(raw) as List)
          .map((e) => HistoryItem.fromJson(e))
          .toList();
    }
  }

  static Future<void> _persist() => _p.setString(
      'history', jsonEncode(history.value.map((e) => e.toJson()).toList()));

  static Future<void> add(String type, String data) async {
    final list = [...history.value]
      ..removeWhere((e) => e.type == type && e.data == data);
    list.insert(0, HistoryItem(type, data, DateTime.now().millisecondsSinceEpoch));
    history.value = list.take(200).toList();
    await _persist();
  }

  static Future<void> remove(HistoryItem item) async {
    history.value = history.value.where((e) => e != item).toList();
    await _persist();
  }

  static Future<void> clear() async {
    history.value = [];
    await _persist();
  }

  // Printer prefs
  static int get paperDots => _p.getInt('paperDots') ?? 384; // 58mm
  static Future<void> setPaperDots(int v) => _p.setInt('paperDots', v);
  static String? get lastPrinterMac => _p.getString('printerMac');
  static String? get lastPrinterName => _p.getString('printerName');
  static String get lastPrinterType => _p.getString('printerType') ?? 'classic';
  static Future<void> saveLastPrinter(String id, String name, String type) async {
    await _p.setString('printerMac', id);
    await _p.setString('printerName', name);
    await _p.setString('printerType', type);
  }
  static int get rotation => _p.getInt('rotation') ?? 0; // 0/90/180/270
  static Future<void> setRotation(int v) => _p.setInt('rotation', v);
  static int get density => _p.getInt('density') ?? 8; // TSPL 0-15
  static Future<void> setDensity(int v) => _p.setInt('density', v);

  // ---- Templates ----
  static LabelTemplate _sample() => LabelTemplate(
        id: newId(), name: 'Product label', folder: 'Samples', wMm: 50, hMm: 30,
        elements: [
          LabelElement(id: newId(), kind: 'text', data: 'Product name',
              x: 3, y: 2, w: 44, h: 7, fontSize: 4.6, bold: true),
          LabelElement(id: newId(), kind: 'barcode', data: '123456789012',
              x: 3, y: 10, w: 44, h: 16),
        ],
      );

  static Future<void> _persistTemplates() => _p.setString('templates',
      jsonEncode(templates.value.map((e) => e.toJson()).toList()));

  static Future<void> saveTemplate(LabelTemplate t) async {
    t.updated = DateTime.now().millisecondsSinceEpoch;
    final list = [...templates.value];
    final i = list.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      list[i] = t;
    } else {
      list.insert(0, t);
    }
    templates.value = list;
    await _persistTemplates();
  }

  static Future<void> deleteTemplate(String id) async {
    templates.value = templates.value.where((e) => e.id != id).toList();
    await _persistTemplates();
  }

  static String exportJson() => jsonEncode({
        'app': 'barcode_studio',
        'v': 1,
        'templates': templates.value.map((e) => e.toJson()).toList(),
      });

  /// Returns number of templates imported (merged, never overwrites).
  static Future<int> importJson(String raw) async {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final list = (j['templates'] as List)
        .map((e) => LabelTemplate.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final existing = templates.value.map((e) => e.id).toSet();
    for (final t in list) {
      if (existing.contains(t.id)) t.id = newId();
    }
    templates.value = [...list, ...templates.value];
    await _persistTemplates();
    return list.length;
  }

  // ---- Printer settings ----
  static String get lang => _p.getString('lang') ?? 'escpos'; // escpos | tspl
  static Future<void> setLang(String v) => _p.setString('lang', v);
  static int get dpi => _p.getInt('dpi') ?? 203;
  static Future<void> setDpi(int v) => _p.setInt('dpi', v);
  static double get gapMm => _p.getDouble('gap') ?? 2.0;
  static Future<void> setGapMm(double v) => _p.setDouble('gap', v);
  static double get quickW => _p.getDouble('qw') ?? 50;
  static double get quickH => _p.getDouble('qh') ?? 30;
  static Future<void> setQuickSize(double w, double h) async {
    await _p.setDouble('qw', w);
    await _p.setDouble('qh', h);
  }

  // ---- Saved custom label sizes (mm) ----
  static List<List<double>> get customSizes {
    final raw = _p.getString('sizes');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
        .toList();
  }

  static Future<void> saveCustomSizes(List<List<double>> v) =>
      _p.setString('sizes', jsonEncode(v));

  // ---- A4 sheet settings ----
  static Map<String, dynamic> get sheetCfg {
    final raw = _p.getString('sheet');
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw));
  }

  static Future<void> saveSheetCfg(Map<String, dynamic> m) =>
      _p.setString('sheet', jsonEncode(m));
}
