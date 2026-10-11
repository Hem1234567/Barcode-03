import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'editor_screen.dart';

enum _Sort { name, newest, oldest }

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  String _q = '';
  String _folder = ''; // '' = all
  _Sort _sort = _Sort.newest;

  void _open(LabelTemplate t) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(CupertinoPageRoute(
        builder: (_) => EditorScreen(template: t.copy())));
  }

  Future<void> _create() async {
    final size = await pickLabelSize(context);
    if (size == null) return;
    final t = LabelTemplate(
        id: newId(), name: 'New label', folder: _folder, wMm: size.$1, hMm: size.$2);
    await Store.saveTemplate(t);
    if (mounted) _open(t);
  }

  void _sortSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: const Text('Sort by'),
        actions: [
          for (final e in {
            _Sort.name: 'Name (A–Z)',
            _Sort.newest: 'Newest first',
            _Sort.oldest: 'Oldest first'
          }.entries)
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() => _sort = e.key);
                Navigator.pop(c);
              },
              child: Text(e.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
      ),
    );
  }

  void _backupSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: const Text('Backup templates'),
        message: const Text('Export a file you can keep, then import it on a new phone.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(c);
              final dir = await getTemporaryDirectory();
              final f = File('${dir.path}/label_templates_backup.json');
              await f.writeAsString(Store.exportJson());
              await Share.shareXFiles([XFile(f.path)]);
            },
            child: const Text('Export backup file'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(c);
              final data = await Clipboard.getData('text/plain');
              try {
                final n = await Store.importJson(data?.text ?? '');
                if (mounted) showInfo(context, 'Imported $n template(s).');
              } catch (_) {
                if (mounted) {
                  showInfo(context,
                      'Open the backup file, copy all of its text, then try again.',
                      title: 'Clipboard has no backup');
                }
              }
            },
            child: const Text('Import from clipboard'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
      ),
    );
  }

  void _itemSheet(LabelTemplate t) {
    HapticFeedback.mediumImpact();
    showCupertinoModalPopup(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: Text(t.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(c);
              final n = await askText(context, 'Rename', t.name);
              if (n != null && n.isNotEmpty) {
                t.name = n;
                Store.saveTemplate(t);
              }
            },
            child: const Text('Rename'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(c);
              final n = await askText(context, 'Folder', t.folder,
                  placeholder: 'Folder name (empty = none)');
              if (n != null) {
                t.folder = n;
                Store.saveTemplate(t);
              }
            },
            child: const Text('Move to folder…'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(c);
              final d = t.copy()
                ..id = newId()
                ..name = '${t.name} copy';
              Store.saveTemplate(d);
            },
            child: const Text('Duplicate'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(c);
              Store.deleteTemplate(t.id);
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppColors.text(context);
    final sub = AppColors.subtext(context);
    return CupertinoPageScaffold(
      child: ValueListenableBuilder<List<LabelTemplate>>(
        valueListenable: Store.templates,
        builder: (context, all, _) {
          final folders = all.map((e) => e.folder).where((f) => f.isNotEmpty).toSet().toList()..sort();
          if (_folder.isNotEmpty && !folders.contains(_folder)) _folder = '';
          var list = all.where((t) {
            if (_folder.isNotEmpty && t.folder != _folder) return false;
            if (_q.isEmpty) return true;
            return t.name.toLowerCase().contains(_q.toLowerCase());
          }).toList();
          switch (_sort) {
            case _Sort.name:
              list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            case _Sort.newest:
              list.sort((a, b) => b.updated.compareTo(a.updated));
            case _Sort.oldest:
              list.sort((a, b) => a.updated.compareTo(b.updated));
          }
          return CustomScrollView(slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: const Text('Labels'),
              border: null,
              leading: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _backupSheet,
                  child: const Text('Backup')),
              trailing: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _create,
                  child: const Icon(CupertinoIcons.add_circled, size: 28)),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Row(children: [
                  Expanded(
                    child: CupertinoSearchTextField(
                      placeholder: 'Search templates',
                      style: TextStyle(color: text),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                  CupertinoButton(
                      padding: const EdgeInsets.only(left: 12),
                      minSize: 32,
                      onPressed: _sortSheet,
                      child: const Icon(CupertinoIcons.sort_down)),
                ]),
              ),
            ),
            if (folders.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final f in ['', ...folders])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _folder = f);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                  color: _folder == f
                                      ? AppColors.accent
                                      : AppColors.surface(context),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(f.isEmpty ? 'All' : f,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: _folder == f
                                          ? CupertinoColors.white
                                          : text)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                    child: Text(all.isEmpty ? 'Tap + to create a label' : 'No matches',
                        style: TextStyle(color: sub))),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = list[i];
                    return Dismissible(
                      key: ValueKey(t.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                            color: CupertinoColors.destructiveRed,
                            borderRadius: BorderRadius.circular(14)),
                        child: const Icon(CupertinoIcons.delete,
                            color: CupertinoColors.white),
                      ),
                      onDismissed: (_) => Store.deleteTemplate(t.id),
                      child: GestureDetector(
                        onTap: () => _open(t),
                        onLongPress: () => _itemSheet(t),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: AppColors.surface(context),
                              borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            const Icon(CupertinoIcons.tag, color: AppColors.accent),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: text,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(
                                        '${t.wMm.toStringAsFixed(0)} × ${t.hMm.toStringAsFixed(0)} mm'
                                        '${t.folder.isEmpty ? '' : '  ·  ${t.folder}'}',
                                        style: TextStyle(color: sub, fontSize: 13)),
                                  ]),
                            ),
                            const Icon(CupertinoIcons.chevron_forward,
                                size: 16, color: CupertinoColors.systemGrey),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}
