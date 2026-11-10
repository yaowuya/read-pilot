import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../services/read_aloud.dart';
import '../components/book_cover.dart';
import '../components/design.dart';
import '../theme.dart';

/// 设计稿听书页的基础落地：系统 TTS 播放/暂停、上一章/下一章、回目录。
/// 睡眠定时与 15 秒快进在系统 TTS 下不可靠，本页不提供。
class AudioScreen extends StatefulWidget {
  const AudioScreen({
    super.key,
    required this.controller,
    required this.book,
    required this.chapterIndex,
    required this.readAloud,
    required this.onChapterChanged,
    required this.onOpenToc,
  });

  final AppController controller;
  final Book book;
  final int chapterIndex;
  final ReadAloudController readAloud;
  final ValueChanged<int> onChapterChanged;
  final VoidCallback onOpenToc;

  @override
  State<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> {
  Book get book => widget.book;
  int get chapterIndex => widget.chapterIndex;

  String get _chapterTitle {
    if (chapterIndex < 0 || chapterIndex >= book.chapters.length) {
      return book.title;
    }
    return book.chapters[chapterIndex].title;
  }

  Future<void> _toggle() async {
    if (widget.readAloud.isSpeaking) {
      await widget.readAloud.stop();
    } else {
      final chapter = book.chapters[chapterIndex];
      final text = ReadAloudText.fromParagraphs(chapter.paragraphs);
      await widget.readAloud.start(text);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.readAloud,
      builder: (context, _) {
        final speaking = widget.readAloud.isSpeaking;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppTopBar(
            onBack: () => Navigator.of(context).maybePop(),
            title: '听书',
            actions: [
              IconButton(
                tooltip: '目录',
                onPressed: widget.onOpenToc,
                icon: const Icon(Icons.list_alt_outlined),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
            children: [
              Center(
                child: BookCover(
                  book: book,
                  imageLoader: widget.controller.loadBookCover,
                  width: 148,
                  height: 210,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                book.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '第 ${chapterIndex + 1} 章 · $_chapterTitle',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const Key('audio-prev'),
                    tooltip: '上一章',
                    onPressed: chapterIndex == 0
                        ? null
                        : () => widget.onChapterChanged(chapterIndex - 1),
                    icon: const Icon(Icons.skip_previous, size: 32),
                  ),
                  const SizedBox(width: 18),
                  FilledButton(
                    key: const Key('audio-toggle'),
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      minimumSize: const Size(72, 72),
                    ),
                    onPressed: _toggle,
                    child: Icon(
                      speaking ? Icons.pause : Icons.play_arrow,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 18),
                  IconButton(
                    key: const Key('audio-next'),
                    tooltip: '下一章',
                    onPressed: chapterIndex + 1 >= book.chapters.length
                        ? null
                        : () => widget.onChapterChanged(chapterIndex + 1),
                    icon: const Icon(Icons.skip_next, size: 32),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                speaking ? '正在朗读本章' : '系统朗读 · 点播放开始',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              const InfoNote(lines: ['听书使用设备自带语音引擎。', '睡眠定时与快进在本版本暂不提供。']),
            ],
          ),
        );
      },
    );
  }
}
