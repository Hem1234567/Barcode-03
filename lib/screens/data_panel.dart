import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import '../models.dart';
import '../services/sheet_import.dart';
import '../theme.dart';
import '../widgets.dart';

/// Where the numbers / text for each label come from.
class DataPanel extends StatefulWidget {
  final LabelTemplate t;
  final VoidCallback onChanged;
  const DataPanel({super.key, required this.t, required this.onChanged});
  @override
  State<DataPanel> createState() => _DataPanelState();
}

class _DataPanelState extends State<DataPanel> {
  late final TextEditingController _list = TextEditingController(
      text: widget.t.dataMode == 'list'
          ? widget.t.rows.map((r) => r.join(', ')).join('\n')
          : '');
  bool _skipHeader = true;
  String _file = '';

  LabelTemplate get t => widget.t;

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  void _parseList(String v) {
    t.rows = v
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => l.split(RegExp(r'[\t,]')).map((c) => c.trim()).toList())
        .toList();
    _changed();
  }

  Future<void> _pickFile() async {
    try {
      final r = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['xlsx', 'csv', 'txt', 'tsv'],
          withData: true);
      final f = r?.files.firstOrNull;
      if (f == null || f.bytes == null) return;
      final ext = (f.extension ?? '').toLowerCase();
      var rows = ext == 'xlsx'
          ? parseXlsx(f.bytes!)
          : parseCsv(utf8.decode(f.bytes!, allowMalformed: true));
      if (_skipHeader && rows.isNotEmpty) rows = rows.sublist(1);
      if (rows.isEmpty) {
        if (mounted) showInfo(context, 'No data rows found in that file.');
        return;
      }
      t.rows = rows;
      t.dataMode = 'excel';
      _file = f.name;
      _changed();
    } catch (e) {
      if (mounted) {
        showInfo(context,
            'Could not read that file. Use .xlsx or .csv (in Excel: File › Save As › CSV or Excel Workbook).',
            title: 'Import failed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppColors.text(context);
    final sub = AppColors.subtext(context);
    final count = t.generateRows().length;

    Widget card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.surface(context), borderRadius: BorderRadius.circular(14)),
        child: child);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        Text(
            'Put {n} in any text, barcode or QR box. Each label prints with the next value. '
            'Example: "ABC-{n}". With Excel, use {1}, {2}, {3} for columns.',
            style: TextStyle(color: sub, fontSize: 13)),
        const SizedBox(height: 14),
        segmented<String>(
            context,
            t.dataMode,
            {'none': 'Off', 'range': 'Start–End', 'list': 'Custom', 'excel': 'Excel'},
            (v) {
          t.dataMode = v;
          if (v == 'list') _parseList(_list.text);
          _changed();
        }),
        const SizedBox(height: 16),
        if (t.dataMode == 'range')
          card(Column(children: [
            Row(children: [
              Expanded(
                  child: NumBox(
                      label: 'Starting number',
                      decimals: 0,
                      value: t.rangeStart.toDouble(),
                      onChanged: (v) {
                        t.rangeStart = v.toInt();
                        _changed();
                      })),
              const SizedBox(width: 12),
              Expanded(
                  child: NumBox(
                      label: 'Ending number',
                      decimals: 0,
                      value: t.rangeEnd.toDouble(),
                      onChanged: (v) {
                        t.rangeEnd = v.toInt();
                        _changed();
                      })),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: NumBox(
                      label: 'Step (+1, +5, -1…)',
                      decimals: 0,
                      value: t.rangeStep.toDouble(),
                      onChanged: (v) {
                        t.rangeStep = v.toInt();
                        _changed();
                      })),
              const SizedBox(width: 12),
              Expanded(
                  child: NumBox(
                      label: 'Digits (zero pad)',
                      decimals: 0,
                      value: t.rangePad.toDouble(),
                      onChanged: (v) {
                        t.rangePad = v.toInt().clamp(0, 20).toInt();
                        _changed();
                      })),
            ]),
          ])),
        if (t.dataMode == 'list')
          CupertinoTextField(
            controller: _list,
            minLines: 6,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            placeholder: 'One label per line:\n1001\n1005\n2040\n(or  name, price  for two columns)',
            padding: const EdgeInsets.all(12),
            style: TextStyle(color: text),
            placeholderStyle: TextStyle(color: sub),
            decoration: BoxDecoration(
                color: AppColors.surface(context), borderRadius: BorderRadius.circular(12)),
            onChanged: _parseList,
          ),
        if (t.dataMode == 'excel')
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('First row is a header', style: TextStyle(color: text))),
              CupertinoSwitch(
                  value: _skipHeader, onChanged: (v) => setState(() => _skipHeader = v)),
            ]),
            const SizedBox(height: 6),
            CupertinoButton.filled(
              borderRadius: BorderRadius.circular(12),
              onPressed: _pickFile,
              child: Text(_file.isEmpty ? 'Choose Excel / CSV file' : 'Change file'),
            ),
            if (_file.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_file, style: TextStyle(color: text, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final r in t.rows.take(4))
                Text(
                    [for (var i = 0; i < r.length && i < 6; i++) '{${i + 1}} ${r[i]}']
                        .join('   '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: sub, fontSize: 12)),
            ],
            const SizedBox(height: 6),
            Text('Supports .xlsx and .csv. Re-pick the file after changing the header switch.',
                style: TextStyle(color: sub, fontSize: 12)),
          ])),
        const SizedBox(height: 16),
        Center(
          child: Text(
              t.dataMode == 'none'
                  ? 'Data is off: prints one design.'
                  : '$count label${count == 1 ? '' : 's'} will be made',
              style: TextStyle(color: text, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
