import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'common.dart';

/// Presents bounded source-search states and delegates switching to the controller.
class SourceSwitchSheet extends StatefulWidget {
  const SourceSwitchSheet({
    super.key,
    required this.controller,
    required this.book,
  });

  final AppController controller;
  final Book book;

  @override
  State<SourceSwitchSheet> createState() => _SourceSwitchSheetState();
}

class _SourceSwitchSheetState extends State<SourceSwitchSheet> {
  SourceCandidateSearchResult? _result;
  Completer<void>? _abort;
  String? _error;
  String? _switchingId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    super.dispose();
  }

  Future<void> _load() async {
    if (!(_abort?.isCompleted ?? true)) _abort!.complete();
    final abort = Completer<void>();
    setState(() {
      _abort = abort;
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.controller.findSourceCandidates(
        widget.book.id,
        abortTrigger: abort.future,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
        _abort = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(error);
        _loading = false;
        _abort = null;
      });
    }
  }

  Future<void> _switch(Book candidate) async {
    if (_switchingId != null) return;
    setState(() {
      _switchingId = candidate.id;
      _error = null;
    });
    try {
      final switched = await widget.controller.switchBookSource(
        widget.book.id,
        candidate,
      );
      if (mounted) Navigator.pop(context, switched);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(error);
        _switchingId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '为《${widget.book.title}》换源',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: _switchingId == null
                      ? () => Navigator.pop(context)
                      : null,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (result != null && result.failedSources > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                '${result.failedSources} 个书源暂时不可用，已显示其他候选。',
                key: const Key('source-switch-partial-error'),
                style: const TextStyle(color: Color(0xFF9B5A20)),
              ),
            ),
          if (_error != null)
            Padding(
              key: const Key('source-switch-error'),
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: QuietPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB54444)),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _switchingId == null ? _load : null,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(
                    key: Key('source-switch-loading'),
                    child: CircularProgressIndicator(),
                  )
                : result == null
                ? const SizedBox.shrink()
                : result.candidates.isEmpty
                ? const Center(
                    key: Key('source-switch-empty'),
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('没有找到其他同名书源。'),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: result.candidates.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final candidate = result.candidates[index];
                      final switching = _switchingId == candidate.id;
                      return ListTile(
                        key: Key('source-candidate-${candidate.id}'),
                        enabled: _switchingId == null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        leading: BookCover(
                          book: candidate,
                          imageLoader: widget.controller.loadBookCover,
                          width: 44,
                          height: 62,
                        ),
                        title: Text(candidate.title),
                        subtitle: Text(
                          '${candidate.author} · ${candidate.sourceLabel}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        trailing: switching
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () => _switch(candidate),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
