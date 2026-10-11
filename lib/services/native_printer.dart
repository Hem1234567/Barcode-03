import 'package:flutter/services.dart';

class PrinterDevice {
  final String name, id, type; // type: classic | ble | usb
  const PrinterDevice(this.name, this.id, this.type);
  String get typeLabel => switch (type) {
        'ble' => 'Bluetooth LE',
        'usb' => 'USB',
        _ => 'Bluetooth',
      };
}

/// Thin wrapper over the Kotlin transport in MainActivity.kt.
class NativePrinter {
  static const _ch = MethodChannel('barcode_studio/printer');

  static Future<List<PrinterDevice>> _list(String m, [Map<String, dynamic>? a]) async {
    final r = await _ch.invokeListMethod<Map>(m, a) ?? [];
    return r
        .map((e) => PrinterDevice('${e['name']}', '${e['id']}', '${e['type']}'))
        .toList();
  }

  static Future<List<PrinterDevice>> bonded() => _list('bonded');
  static Future<List<PrinterDevice>> usb() => _list('usb');
  static Future<List<PrinterDevice>> scanBle({int ms = 5000}) => _list('scanBle', {'ms': ms});

  static Future<bool> connect(PrinterDevice d) async =>
      (await _ch.invokeMethod<bool>('connect', {'type': d.type, 'id': d.id})) ?? false;

  static Future<bool> write(List<int> bytes, {int delayMs = 20}) async =>
      (await _ch.invokeMethod<bool>(
          'write', {'bytes': Uint8List.fromList(bytes), 'delay': delayMs})) ??
      false;

  static Future<void> disconnect() => _ch.invokeMethod('disconnect');
  static Future<bool> isConnected() async =>
      (await _ch.invokeMethod<bool>('isConnected')) ?? false;
}
