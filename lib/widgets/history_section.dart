import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../screens/history_page.dart';
import '../screens/result_page.dart';
import '../services/result_service.dart';

/// Dashboard block for the home page: totals + the latest 3 screenings + "View all".
/// Put it in the home page column, only when the user is signed in.
/// Change [refreshTick] (e.g. after a new screening) to make it reload.
class HistorySection extends StatefulWidget {
  final String baseUrl;
  final Future<String?> Function() getToken;
  final int refreshTick;
  const HistorySection({super.key, required this.baseUrl, required this.getToken, this.refreshTick = 0});

  @override
  State<HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<HistorySection> {
  late final _service = ResultService(baseUrl: widget.baseUrl, getToken: widget.getToken);
  List<RecordItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HistorySection old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _load();
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

  void _openAll() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HistoryPage(baseUrl: widget.baseUrl, getToken: widget.getToken)));

  void _open(RecordItem it) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ResultPage(scanId: it.scanId, baseUrl: widget.baseUrl, getToken: widget.getToken)));

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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

  @override
  Widget build(BuildContext context) {
    final s = HistoryStats.from(_items);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.assignment_turned_in_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('My results and history',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink))),
              IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
              TextButton(onPressed: _openAll, child: const Text('View all')),
            ]),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger))
            else ...[
              Wrap(spacing: 10, runSpacing: 10, children: [
                _chip(Icons.history, '${s.total} screenings'),
                _chip(Icons.event_outlined, 'Last: ${s.lastDate}'),
                if (s.mostCommon != null) _chip(Icons.biotech_outlined, 'Most common: ${s.mostCommon}'),
              ]),
              const SizedBox(height: 12),
              if (_items.isEmpty)
                const Text('No screenings yet. Tap "Start screening" to begin.',
                    style: TextStyle(color: AppColors.muted))
              else
                for (final it in _items.take(3)) ...[
                  HistoryTile(
                    item: it,
                    onOpen: () => _open(it),
                    onEditNote: () => _editNote(it),
                    onDelete: () => _delete(it),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ]),
        ),
      ),
    );
  }

  Widget _chip(IconData i, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
}