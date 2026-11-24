import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/result_service.dart';
import 'result_page.dart';
import 'scan_page.dart';

String formatDate(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

/// Asks the user to type a short note for a screening. Returns the text, or null if cancelled.
Future<String?> askNote(BuildContext context, String? current) {
  final ctl = TextEditingController(text: current ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('My note'),
      content: TextField(
        controller: ctl,
        maxLength: 500,
        maxLines: 4,
        autofocus: true,
        decoration: const InputDecoration(
            hintText: 'For example: used the cream I bought, rash is smaller now'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

/// Asks for confirmation before deleting. Returns true only when the user confirms.
Future<bool> confirmDelete(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this screening?'),
      content: const Text('The answers, the photo and the result will be permanently deleted. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Summary numbers for the dashboard cards.
class HistoryStats {
  final int total;
  final String lastDate;
  final String? mostCommon;
  const HistoryStats(this.total, this.lastDate, this.mostCommon);

  factory HistoryStats.from(List<RecordItem> items) {
    if (items.isEmpty) return const HistoryStats(0, '-', null);
    final count = <String, int>{};
    for (final i in items) {
      final c = i.topCondition;
      if (c != null) count[c] = (count[c] ?? 0) + 1;
    }
    String? best;
    count.forEach((k, v) {
      if (best == null || v > count[best]!) best = k;
    });
    return HistoryStats(items.length, formatDate(items.first.scannedAt), best);
  }
}

/// One history row: condition, date, short description, and a result icon button.
class HistoryTile extends StatelessWidget {
  final RecordItem item;
  final VoidCallback onOpen;
  final VoidCallback? onEditNote;
  final VoidCallback? onDelete;
  const HistoryTile({
    super.key,
    required this.item,
    required this.onOpen,
    this.onEditNote,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final conf = item.topConfidence;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.biotech_outlined, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(item.topCondition ?? 'No result',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  if (conf != null)
                    Text('${(conf * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                ]),
                const SizedBox(height: 2),
                Text(formatDate(item.scannedAt),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 6),
                Text(item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, height: 1.4)),
                if ((item.note ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E6), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.sticky_note_2_outlined, size: 14, color: AppColors.warning),
                      const SizedBox(width: 6),
                      Flexible(child: Text(item.note!, style: const TextStyle(fontSize: 12.5))),
                    ]),
                  ),
                ],
              ]),
            ),
            IconButton(
              tooltip: 'View result',
              onPressed: onOpen,
              icon: const Icon(Icons.assignment_turned_in_outlined, color: AppColors.primary),
            ),
            if (onEditNote != null || onDelete != null)
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  if (v == 'note') onEditNote?.call();
                  if (v == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => [
                  if (onEditNote != null)
                    const PopupMenuItem(value: 'note', child: Text('Edit my note')),
                  if (onDelete != null)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ]),
        ),
      ),
    );
  }
}

/// Dashboard: totals at the top, then every past screening (newest first).
class HistoryPage extends StatefulWidget {
  final String baseUrl;
  final Future<String?> Function() getToken;
  const HistoryPage({super.key, required this.baseUrl, required this.getToken});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final _service = ResultService(baseUrl: widget.baseUrl, getToken: widget.getToken);
  List<RecordItem> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _service.list();
    if (!mounted) return;
    setState(() {
      _items = r.items;
      _error = r.error;
      _loading = false;
    });
  }

  void _open(RecordItem it) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ResultPage(scanId: it.scanId, baseUrl: widget.baseUrl, getToken: widget.getToken),
      ));

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // Create: a new screening
  Future<void> _create() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScanPage(baseUrl: widget.baseUrl, getToken: widget.getToken),
    ));
    if (mounted) _load();
  }

  // Update: the person's own note
  Future<void> _editNote(RecordItem it) async {
    final text = await askNote(context, it.note);
    if (text == null) return;
    final err = await _service.updateNote(it.scanId, text);
    if (!mounted) return;
    if (err != null) {
      _snack(err);
    } else {
      _snack('Note saved.');
      _load();
    }
  }

  // Delete
  Future<void> _delete(RecordItem it) async {
    if (!await confirmDelete(context)) return;
    final err = await _service.delete(it.scanId);
    if (!mounted) return;
    if (err != null) {
      _snack(err);
    } else {
      _snack('Screening deleted.');
      _load();
    }
  }

  Widget _stat(IconData icon, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = HistoryStats.from(_items);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('My results and history'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New screening'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Try again')),
                ]))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(padding: const EdgeInsets.all(16), children: [
                      Row(children: [
                        _stat(Icons.history, '${s.total}', 'Screenings'),
                        const SizedBox(width: 10),
                        _stat(Icons.event_outlined, s.lastDate, 'Last screening'),
                        const SizedBox(width: 10),
                        _stat(Icons.biotech_outlined, s.mostCommon ?? '-', 'Most common result'),
                      ]),
                      const SizedBox(height: 16),
                      if (_items.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('No screenings yet. Tap "Start screening" on the home page.')))
                      else
                        for (final it in _items) ...[
                          HistoryTile(
                            item: it,
                            onOpen: () => _open(it),
                            onEditNote: () => _editNote(it),
                            onDelete: () => _delete(it),
                          ),
                          const SizedBox(height: 10),
                        ],
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Screening results are not a diagnosis.',
                            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      ),
                    ]),
                  ),
                ),
    );
  }
}