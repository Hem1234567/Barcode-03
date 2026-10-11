import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'services/store.dart';
import 'theme.dart';

void showInfo(BuildContext context, String msg, {String? title}) {
  showCupertinoDialog(
    context: context,
    builder: (c) => CupertinoAlertDialog(
      title: title == null ? null : Text(title),
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

Future<bool> confirmDialog(BuildContext context, String msg, {String ok = 'Print'}) async {
  final r = await showCupertinoDialog<bool>(
    context: context,
    builder: (c) => CupertinoAlertDialog(
      content: Text(msg),
      actions: [
        CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(c, true),
            child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(BuildContext context, String title, String initial,
    {String placeholder = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showCupertinoDialog<String>(
    context: context,
    builder: (c) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
            controller: ctrl, placeholder: placeholder, autofocus: true),
      ),
      actions: [
        CupertinoDialogAction(
            onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
}

/// Shows a progress dialog while [work] runs. [work] should poll cancelled().
Future<void> runWithProgress(
  BuildContext context,
  String title,
  int total,
  Future<void> Function(void Function(int done) report, bool Function() cancelled) work,
) async {
  final prog = ValueNotifier<int>(0);
  var cancel = false;
  showCupertinoDialog(
    context: context,
    barrierDismissible: false,
    builder: (c) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ValueListenableBuilder<int>(
          valueListenable: prog,
          builder: (_, v, __) => Column(children: [
            const CupertinoActivityIndicator(),
            const SizedBox(height: 10),
            Text('$v / $total'),
          ]),
        ),
      ),
      actions: [
        CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => cancel = true,
            child: const Text('Stop')),
      ],
    ),
  );
  try {
    await work((d) => prog.value = d, () => cancel);
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// A tall sheet that slides up while the page behind stays painted.
Future<T?> showSheet<T>(BuildContext context, String title, WidgetBuilder body,
    {double height = 0.86}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (c) {
      final h = MediaQuery.sizeOf(c).height * height;
      return Container(
        height: h,
        decoration: BoxDecoration(
          color: AppColors.bg(c),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(children: [
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          inherit: false,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text(c),
                          decoration: TextDecoration.none))),
              CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Done')),
            ]),
          ),
          Expanded(child: Builder(builder: body)),
        ]),
      );
    },
  );
}

Widget segmented<T extends Object>(BuildContext context, T value,
    Map<T, String> labels, ValueChanged<T> onChanged) {
  return SizedBox(
    width: double.infinity,
    child: CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      thumbColor: AppColors.isDark(context)
          ? const Color(0xFF3A3A3C)
          : CupertinoColors.white,
      children: {
        for (final e in labels.entries)
          e.key: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(e.value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text(context))),
          )
      },
      onValueChanged: (v) {
        if (v == null) return;
        HapticFeedback.selectionClick();
        onChanged(v);
      },
    ),
  );
}

/// Small labelled number field that keeps the cursor stable while typing.
class NumBox extends StatefulWidget {
  final String label;
  final double value;
  final int decimals;
  final ValueChanged<double> onChanged;
  const NumBox(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged,
      this.decimals = 1});
  @override
  State<NumBox> createState() => _NumBoxState();
}

class _NumBoxState extends State<NumBox> {
  late final TextEditingController _c = TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();
  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  @override
  void didUpdateWidget(NumBox old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) {
      final t = _fmt(widget.value);
      if (_c.text != t) _c.text = t;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label,
          style: TextStyle(fontSize: 12, color: AppColors.subtext(context))),
      const SizedBox(height: 3),
      CupertinoTextField(
        controller: _c,
        focusNode: _focus,
        keyboardType: TextInputType.numberWithOptions(
            decimal: widget.decimals > 0, signed: false),
        textAlign: TextAlign.center,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        style: TextStyle(color: AppColors.text(context), fontSize: 15),
        decoration: BoxDecoration(
            color: AppColors.surface(context), borderRadius: BorderRadius.circular(9)),
        onChanged: (v) {
          final d = double.tryParse(v);
          if (d != null) widget.onChanged(d);
        },
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Label size picker: presets, any custom size (mm or inch), saved sizes.
// ---------------------------------------------------------------------------
Future<(double, double)?> pickLabelSize(BuildContext context, {(double, double)? initial}) {
  return showCupertinoModalPopup<(double, double)>(
    context: context,
    builder: (c) => _SizeSheet(initial: initial),
  );
}

class _SizeSheet extends StatefulWidget {
  final (double, double)? initial;
  const _SizeSheet({this.initial});
  @override
  State<_SizeSheet> createState() => _SizeSheetState();
}

class _SizeSheetState extends State<_SizeSheet> {
  late double w = widget.initial?.$1 ?? 50;
  late double h = widget.initial?.$2 ?? 30;
  bool inch = false;
  List<List<double>> saved = Store.customSizes;

  static const presets = <(double, double)>[
    (25, 15), (30, 20), (38, 25), (40, 20), (40, 30), (45, 30), (50, 25),
    (50, 30), (50, 50), (58, 40), (60, 40), (70, 37), (70, 50), (75, 50),
    (80, 50), (100, 50), (100, 100), (100, 150), (148, 210), (210, 297),
    (50.8, 25.4), (76.2, 50.8), (101.6, 50.8), (101.6, 76.2), (101.6, 152.4),
  ];

  double get _k => inch ? 25.4 : 1;
  String _fmt(double mm) {
    final v = mm / _k;
    final s = v.toStringAsFixed(inch ? 2 : 1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  bool get _valid => w >= 5 && h >= 5 && w <= 600 && h <= 600;

  void _pick((double, double) p) => Navigator.pop(context, p);

  @override
  Widget build(BuildContext context) {
    final text = AppColors.text(context);
    final sub = AppColors.subtext(context);
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.86,
      decoration: BoxDecoration(
        color: AppColors.bg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(children: [
            CupertinoButton(
                onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            Expanded(
                child: Center(
                    child: Text('Label size',
                        style: TextStyle(
                            inherit: false,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: text,
                            decoration: TextDecoration.none)))),
            CupertinoButton(
                onPressed: _valid ? () => _pick((w, h)) : null, child: const Text('Use')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            segmented<bool>(context, inch, {false: 'Millimetres', true: 'Inches'},
                (v) => setState(() => inch = v)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: NumBox(
                      label: 'Width (${inch ? 'in' : 'mm'})',
                      value: w / _k,
                      decimals: inch ? 2 : 1,
                      onChanged: (v) => setState(() => w = v * _k))),
              const SizedBox(width: 12),
              Expanded(
                  child: NumBox(
                      label: 'Height (${inch ? 'in' : 'mm'})',
                      value: h / _k,
                      decimals: inch ? 2 : 1,
                      onChanged: (v) => setState(() => h = v * _k))),
            ]),
            Row(children: [
              Expanded(
                  child: Text('${w.toStringAsFixed(1)} × ${h.toStringAsFixed(1)} mm',
                      style: TextStyle(color: sub, fontSize: 13))),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _valid
                    ? () async {
                        final list = [...saved];
                        if (!list.any((e) => e[0] == w && e[1] == h)) {
                          list.add([w, h]);
                          await Store.saveCustomSizes(list);
                          setState(() => saved = list);
                        }
                      }
                    : null,
                child: const Text('Save this size'),
              ),
            ]),
          ]),
        ),
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              if (saved.isNotEmpty) ...[
                Text('MY SIZES', style: TextStyle(color: sub, fontSize: 13)),
                const SizedBox(height: 6),
                for (final s in saved)
                  _row(context, '${_fmt(s[0])} × ${_fmt(s[1])} ${inch ? 'in' : 'mm'}',
                      () => _pick((s[0], s[1])),
                      onDelete: () async {
                        final list = saved.where((e) => e != s).toList();
                        await Store.saveCustomSizes(list);
                        setState(() => saved = list);
                      }),
                const SizedBox(height: 14),
              ],
              Text('PRESETS', style: TextStyle(color: sub, fontSize: 13)),
              const SizedBox(height: 6),
              for (final p in presets)
                _row(context, '${_fmt(p.$1)} × ${_fmt(p.$2)} ${inch ? 'in' : 'mm'}',
                    () => _pick(p)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, String label, VoidCallback onTap,
      {VoidCallback? onDelete}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: AppColors.surface(context), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      inherit: false,
                      fontSize: 16,
                      color: AppColors.text(context),
                      decoration: TextDecoration.none))),
          if (onDelete != null)
            GestureDetector(
                onTap: onDelete,
                child: const Icon(CupertinoIcons.delete,
                    size: 18, color: CupertinoColors.destructiveRed)),
        ]),
      ),
    );
  }
}
