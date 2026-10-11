import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../main.dart' show tabController;
import '../services/store.dart';
import '../theme.dart';
import 'home_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = AppColors.text(context);
    return CupertinoPageScaffold(
      child: ValueListenableBuilder<List<HistoryItem>>(
        valueListenable: Store.history,
        builder: (context, items, _) => CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: const Text('History'),
              border: null,
              trailing: items.isEmpty
                  ? null
                  : CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => showCupertinoDialog(
                        context: context,
                        builder: (c) => CupertinoAlertDialog(
                          title: const Text('Clear all?'),
                          actions: [
                            CupertinoDialogAction(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('Cancel')),
                            CupertinoDialogAction(
                                isDestructiveAction: true,
                                onPressed: () {
                                  Store.clear();
                                  Navigator.pop(c);
                                },
                                child: const Text('Clear')),
                          ],
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('Nothing saved yet',
                      style: TextStyle(color: AppColors.subtext(context))),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final it = items[i];
                    final type = CodeType.values.firstWhere((t) => t.name == it.type);
                    return Dismissible(
                      key: ValueKey('${it.type}${it.data}${it.ts}'),
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
                      onDismissed: (_) => Store.remove(it),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Store.loadRequest.value = it;
                          tabController.index = 1;
                        },
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
                                    Text(it.data,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: text,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(type.label,
                                        style: TextStyle(
                                            color: AppColors.subtext(context),
                                            fontSize: 13)),
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
          ],
        ),
      ),
    );
  }
}
