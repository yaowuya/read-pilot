import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../theme.dart';
import 'book_cover.dart';
import 'common.dart';

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
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final book = widget.controller.book(widget.book.id) ?? widget.book;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BookCover(book: book, width: 106, height: 148),
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
                style: const TextStyle(color: Color(0xFFB54444), height: 1.8),
              ),
            ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        final added = await widget.controller.addBook(book);
                        if (context.mounted) {
                          Navigator.pop(context);
                          widget.onRead(added);
                        }
                      } catch (error) {
                        if (mounted) {
                          setState(() {
                            _busy = false;
                            _error = errorMessage(error);
                          });
                        }
                      }
                    },
              child: Text(
                _busy
                    ? '正在加载目录…'
                    : widget.controller.book(book.id) == null
                    ? '加入书架并阅读'
                    : '开始阅读',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
