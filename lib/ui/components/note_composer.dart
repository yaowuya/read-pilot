import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../theme.dart';
import 'common.dart';

class NoteComposer extends StatefulWidget {
  const NoteComposer({
    super.key,
    required this.controller,
    required this.book,
    required this.chapterIndex,
    required this.paragraphIndex,
  });
  final AppController controller;
  final Book book;
  final int chapterIndex;
  final int paragraphIndex;
  @override
  State<NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<NoteComposer> {
  final _text = TextEditingController();
  bool _saving = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.book.chapters[widget.chapterIndex];
    final quote =
        chapter.paragraphs[widget.paragraphIndex.clamp(
          0,
          chapter.paragraphs.length - 1,
        )];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        28 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('留住这一页', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              quote,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(height: 1.8, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 18),
          const Text('我的想法（选填）', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            key: const Key('note-input'),
            controller: _text,
            minLines: 3,
            maxLines: 5,
            maxLength: 1200,
            decoration: const InputDecoration(hintText: '写下此刻的想法…'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      try {
                        await widget.controller.addBookmark(
                          Bookmark(
                            id: 'note-${DateTime.now().microsecondsSinceEpoch}',
                            bookId: widget.book.id,
                            chapterIndex: widget.chapterIndex,
                            paragraphIndex: widget.paragraphIndex,
                            quote: quote,
                            note: _text.text.trim(),
                            createdAt: DateTime.now(),
                          ),
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          showMessage(context, '书签已保存，可以从笔记中回到这里。');
                        }
                      } catch (error) {
                        if (context.mounted) {
                          setState(() => _saving = false);
                          showMessage(context, errorMessage(error));
                        }
                      }
                    },
              child: Text(_saving ? '保存中…' : '保存书签'),
            ),
          ),
        ],
      ),
    );
  }
}
