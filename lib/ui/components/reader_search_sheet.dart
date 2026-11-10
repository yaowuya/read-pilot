import 'package:flutter/material.dart';

import '../../domain/book.dart';
import '../../services/book_text_search.dart';
import '../design_icons.dart';
import '../theme.dart';

/// Lets the reader search text already cached for one book.
class ReaderSearchSheet extends StatefulWidget {
  const ReaderSearchSheet({
    super.key,
    required this.book,
    this.displayRulesActive = false,
  });

  final Book book;
  final bool displayRulesActive;

  @override
  State<ReaderSearchSheet> createState() => _ReaderSearchSheetState();
}

class _ReaderSearchSheetState extends State<ReaderSearchSheet> {
  final _query = TextEditingController();
  BookTextSearchResult? _result;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    try {
      final result = const BookTextSearch().search(widget.book, _query.text);
      setState(() {
        _result = result;
        _error = null;
      });
      FocusScope.of(context).unfocus();
    } on FormatException catch (error) {
      setState(() {
        _result = null;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final result = _result;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          height: (MediaQuery.sizeOf(context).height - keyboard) * .82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '书内查找',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            '仅检索已缓存的 ${widget.book.cachedChapters} / ${widget.book.chapters.length} 章',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                        if (widget.displayRulesActive) ...[
                          const SizedBox(height: 8),
                          const Text(
                            '书内查找基于原始缓存；正文替换仅影响显示。',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('reader-search-query'),
                                controller: _query,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => _search(),
                                onChanged: (_) => setState(() {
                                  _result = null;
                                  _error = null;
                                }),
                                decoration: const InputDecoration(
                                  hintText: '查找正文内容',
                                  prefixIcon: Icon(DesignIcons.search, size: 20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              key: const Key('reader-search-submit'),
                              onPressed: _search,
                              child: const Text('查找'),
                            ),
                          ],
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              key: const Key('reader-search-error'),
                              style: const TextStyle(color: Color(0xFFB54444)),
                            ),
                          ),
                        if (result != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            '找到 ${result.hits.length} 段',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '已完整检索 ${result.scannedChapters} / ${result.cachedChapters} 个缓存章节'
                            '${result.truncated ? ' · 结果达到单次上限' : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: result == null
                    ? const Center(child: Text('输入关键词后查找已缓存正文。'))
                    : result.hits.isEmpty
                    ? const Center(child: Text('已缓存章节中没有匹配段落。'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: result.hits.length,
                        itemBuilder: (context, index) {
                          final hit = result.hits[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                key: Key(
                                  'reader-search-hit-${hit.chapterIndex}-${hit.paragraphIndex}',
                                ),
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.pop(context, hit),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hit.chapterTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: hit.excerpt.substring(
                                                0,
                                                hit.highlightStart,
                                              ),
                                            ),
                                            TextSpan(
                                              text: hit.excerpt.substring(
                                                hit.highlightStart,
                                                hit.highlightEnd,
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.blue,
                                              ),
                                            ),
                                            TextSpan(
                                              text: hit.excerpt.substring(
                                                hit.highlightEnd,
                                              ),
                                            ),
                                          ],
                                        ),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.6,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
