import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'common.dart';
import 'source_switch_sheet.dart';

class BookDetails extends StatefulWidget {
  const BookDetails({
    super.key,
    required this.book,
    required this.controller,
    required this.onRead,
  });

  final Book book;
  final AppController controller;
  final ValueChanged<Book> onRead;

  @override
  State<BookDetails> createState() => _BookDetailsState();
}

class _BookDetailsState extends State<BookDetails> {
  String? _busyAction;
  String? _error;

  Future<void> _refreshCover(Book book) async {
    if (_busyAction != null) return;
    setState(() {
      _busyAction = 'cover';
      _error = null;
    });
    try {
      await widget.controller.refreshBookCover(book.id);
      if (mounted) showMessage(context, '封面已刷新。');
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _changeSource(Book book) async {
    if (_busyAction != null) return;
    final switched = await showModalBottomSheet<Book>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) =>
          SourceSwitchSheet(controller: widget.controller, book: book),
    );
    if (mounted && switched != null) {
      setState(() => _error = null);
      showMessage(context, '已切换到 ${switched.sourceLabel}。');
    }
  }

  Future<void> _read(Book book) async {
    if (_busyAction != null) return;
    setState(() {
      _busyAction = 'read';
      _error = null;
    });
    try {
      final added = await widget.controller.addBook(book);
      if (mounted) {
        Navigator.pop(context);
        widget.onRead(added);
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final shelfBook = widget.controller.book(widget.book.id);
      final book = shelfBook ?? widget.book;
      final sourceActions = shelfBook != null && book.isRemote;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 6, 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                BookCover(
                  book: book,
                  imageLoader: widget.controller.loadBookCover,
                  width: 106,
                  height: 148,
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        book.author,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${book.category} · ${book.isExcerpt ? '公版节选' : book.sourceLabel}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (sourceActions) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    key: const Key('book-change-source'),
                    onPressed: _busyAction == null
                        ? () => _changeSource(book)
                        : null,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('换源'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('book-refresh-cover'),
                    onPressed: _busyAction == null
                        ? () => _refreshCover(book)
                        : null,
                    icon: _busyAction == 'cover'
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image_search_outlined, size: 18),
                    label: const Text('刷新封面'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            const Text('关于这本书', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(
              book.description.isEmpty
                  ? '书源未提供简介。添加后会按需加载目录与正文。'
                  : book.description,
              style: const TextStyle(height: 1.9, color: AppColors.muted),
            ),
            if (book.chapters.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                '${book.chapters.length} 个章节 · ${book.cachedChapters} 章已缓存',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              book.provenance,
              style: const TextStyle(
                fontSize: 12,
                height: 1.8,
                color: AppColors.muted,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  key: const Key('book-details-error'),
                  style: const TextStyle(color: Color(0xFFB54444), height: 1.8),
                ),
              ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busyAction == null ? () => _read(book) : null,
                child: Text(
                  _busyAction == 'read'
                      ? '正在加载目录…'
                      : shelfBook == null
                      ? '加入书架并阅读'
                      : '开始阅读',
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
