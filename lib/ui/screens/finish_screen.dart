import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../components/book_cover.dart';
import '../components/design.dart';
import '../components/reading_assistant_sheet.dart';
import '../theme.dart';
import 'notes_screen.dart';

/// 设计稿「读完一本书」全屏：回顾笔记与助手，再回书架。
class FinishScreen extends StatelessWidget {
  const FinishScreen({
    super.key,
    required this.controller,
    required this.book,
    required this.onShelf,
    required this.onOpenNote,
  });

  final AppController controller;
  final Book book;
  final VoidCallback onShelf;
  final ValueChanged<Bookmark> onOpenNote;

  int get _noteCount {
    final marks = controller.readerMarks(book.id).length;
    if (marks > 0) return marks;
    return controller.bookmarks.where((note) => note.bookId == book.id).length;
  }

  int get _dayCount {
    final days = <String>{};
    for (final activity in controller.readingActivities) {
      if (activity.bookId != book.id) continue;
      final local = activity.occurredAt.toLocal();
      days.add('${local.year}-${local.month}-${local.day}');
    }
    return days.length;
  }

  @override
  Widget build(BuildContext context) {
    final notes = _noteCount;
    final days = _dayCount;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppTopBar(
        onBack: onShelf,
        actions: [
          IconButton(
            tooltip: '回到书架',
            onPressed: onShelf,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        children: [
          Center(
            child: BookCover(
              book: book,
              imageLoader: controller.loadBookCover,
              width: 108,
              height: 152,
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '又读完了，一段旅程',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '合上书\n也把一些东西留在心里',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${book.title} · 阅读完成',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              _stat('${book.chapters.length}', '章读完'),
              _stat('$notes', '条笔记'),
              _stat(days == 0 ? '—' : '$days', '天的阅读'),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            key: const Key('finish-notes'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NotesScreen(
                  controller: controller,
                  bookId: book.id,
                  onOpen: onOpenNote,
                ),
              ),
            ),
            icon: const Icon(Icons.notes_outlined),
            label: const Text('回看我的笔记'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('finish-assistant'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              constraints: const BoxConstraints(maxWidth: 620),
              builder: (_) => Theme(
                data: appTheme(),
                child: ReadingAssistantSheet(
                  book: book,
                  chapterTitle: book.chapters.isEmpty
                      ? book.title
                      : book.chapters.last.title,
                  paragraph: '这本书已经读完。下面是根据本机笔记与阅读记录整理的回顾。',
                  readChapters: book.chapters.length,
                  notes: controller.bookmarks
                      .where((note) => note.bookId == book.id)
                      .toList(),
                ),
              ),
            ),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('和助手聊聊这本书'),
          ),
          TextButton(
            key: const Key('finish-shelf'),
            onPressed: onShelf,
            child: const Text('回到书架'),
          ),
          const SizedBox(height: 24),
          const Text(
            '读过的字句，会成为你的另一种记忆。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 2, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    ),
  );
}
