import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../components/common.dart';
import '../theme.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({
    super.key,
    required this.controller,
    required this.onOpen,
    this.bookId,
  });
  final AppController controller;
  final String? bookId;
  final ValueChanged<Bookmark> onOpen;

  @override
  Widget build(BuildContext context) => Theme(
    data: appTheme(),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('书签与笔记', style: TextStyle(fontSize: 18)),
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final notes = controller.bookmarks
              .where((note) => bookId == null || note.bookId == bookId)
              .toList();
          if (notes.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: EmptyState(
                title: '值得记住的，留在这里',
                description: '阅读时点击书签，可收藏当前段落并写下想法。',
              ),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: notes.length,
                separatorBuilder: (_, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final note = notes[index];
                  final book = controller.book(note.bookId);
                  return QuietPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                book?.title ?? '已移除的书籍',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${note.createdAt.month}月${note.createdAt.day}日',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                            IconButton(
                              tooltip: '删除书签',
                              onPressed: () async {
                                if (!await confirmRemoval(
                                  context,
                                  '删除这条书签？',
                                  '书签和这条笔记将从本机移除，不影响书籍正文。',
                                )) {
                                  return;
                                }
                                try {
                                  await controller.deleteBookmark(note.id);
                                } catch (error) {
                                  if (context.mounted) {
                                    showMessage(context, errorMessage(error));
                                  }
                                }
                              },
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 19,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          note.quote,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            height: 1.9,
                          ),
                        ),
                        if (note.note.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(note.note, style: const TextStyle(height: 1.8)),
                        ],
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: book == null ? null : () => onOpen(note),
                          child: const Text('回到书中  →'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}
