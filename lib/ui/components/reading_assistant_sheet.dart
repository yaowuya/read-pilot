import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/book.dart';
import '../theme.dart';

/// 阅读助手：按设计稿是一个从底部弹出的回顾面板。
///
/// 这一版不连模型。回答只由调用方给的本机事实拼出来——当前段落原文、所在
/// 章节、已读章节数、这本书的笔记条目——所以它不会编造作者生平、后文情节或
/// 书里没有的内容。声明固定为「本地回顾 · 不连接模型」。
class ReadingAssistantSheet extends StatefulWidget {
  const ReadingAssistantSheet({
    super.key,
    required this.book,
    required this.chapterTitle,
    required this.paragraph,
    required this.readChapters,
    required this.notes,
  });

  final Book book;
  final String chapterTitle;
  final String paragraph;
  final int readChapters;
  final List<Bookmark> notes;

  @override
  State<ReadingAssistantSheet> createState() => _ReadingAssistantSheetState();
}

enum _AssistantMode { explain, recap, concept }

class _ReadingAssistantSheetState extends State<ReadingAssistantSheet> {
  final _input = TextEditingController();
  var _mode = _AssistantMode.explain;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String get _quote {
    final text = widget.paragraph.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return '（这一段还没有正文）';
    if (text.length <= 90) return '“$text”';
    return '“${text.substring(0, 90)}…”';
  }

  String get _question => switch (_mode) {
    _AssistantMode.explain => '这一段在讲什么？',
    _AssistantMode.recap => '帮我回顾读过的内容',
    _AssistantMode.concept => '这一段里值得留意的说法',
  };

  /// Every sentence below is a restatement of local state. When the local state
  /// is thin the answer says so instead of filling the gap with invented text.
  List<String> get _answer => switch (_mode) {
    _AssistantMode.explain => [
      if (widget.paragraph.trim().isEmpty)
        '这一段没有正文，所以这里没有可回顾的内容。'
      else ...[
        '这一段原文是：$_quote',
        '它的位置是「${widget.chapterTitle}」。',
        widget.readChapters > 0
            ? '这本书你已经读过 ${widget.readChapters} 章，回顾范围也只到这里，不涉及后文。'
            : '这本书还没有留下阅读进度，所以只能看到这一段本身。',
      ],
    ],
    _AssistantMode.recap => [
      if (widget.readChapters > 0)
        '你已经读完 ${widget.readChapters} 章，最近读到「${widget.chapterTitle}」。'
      else
        '这本书还没有读完任何一章，暂时没有可以回顾的进度。',
      if (widget.notes.isNotEmpty)
        '期间留下 ${widget.notes.length} 条笔记，最早一条是：${_noteQuote(widget.notes.first)}'
      else
        '还没有笔记：划线或写下一个想法后，这里就会出现。',
      '合上这一段时，可以只记住一件让你停下来的事。',
    ],
    _AssistantMode.concept => [
      '你选中的是这一段：$_quote',
      if (widget.paragraph.trim().isEmpty)
        '因为没有正文，无法判断它讲了什么。'
      else
        '如果要给它一个说法，可以从「这一段具体描写了什么」和「它让你想到什么」两层来看。',
      '这本书里没有更多上下文可以对照，所以这里不替它下结论。',
    ],
  };

  String _noteQuote(Bookmark note) {
    final quote = note.quote.trim();
    if (quote.isEmpty) return '（未记录引文）';
    if (quote.length <= 40) return '“$quote”';
    return '“${quote.substring(0, 40)}…”';
  }

  Future<void> _copyAnswer() async {
    final text = [
      _question,
      ..._answer,
      '——${widget.chapterTitle}',
      '本地回顾 · 不连接模型',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast('回答已复制');
  }

  Future<void> _saveToNotes() async {
    await Clipboard.setData(
      ClipboardData(
        text:
            '${_answer.join('\n')}\n——${widget.book.title} · ${widget.chapterTitle}',
      ),
    );
    if (mounted) _toast('回顾内容已复制，可直接粘贴到笔记');
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _ask(String question) {
    final text = question.trim();
    if (text.isEmpty) return;
    setState(() {
      _mode = _AssistantMode.explain;
      _input.clear();
    });
    _toast('这一版只看本机已读内容，回答仍基于当前段落');
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadii.sheet),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const Key('reading-assistant'),
          padding: const EdgeInsets.fromLTRB(25, 10, 25, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 33,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDFE3E9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _head(),
              const SizedBox(height: 16),
              _contextChip(),
              const SizedBox(height: 2),
              _questionBubble(),
              const SizedBox(height: 14),
              _answerBlock(),
              const SizedBox(height: 10),
              _referenceChip(),
              const SizedBox(height: 2),
              _answerActions(),
              const SizedBox(height: 14),
              _suggestions(),
              const SizedBox(height: 18),
              _inputBar(),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  '本地回顾 · 不连接模型',
                  key: Key('assistant-disclaimer'),
                  style: TextStyle(fontSize: 9, color: Color(0xFFB0B7C2)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _head() => Row(
    children: [
      Container(
        width: 33,
        height: 33,
        decoration: BoxDecoration(
          color: AppColors.softBlue,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.auto_awesome,
          size: 18,
          color: Color(0xFF5789CB),
        ),
      ),
      const SizedBox(width: 10),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '阅读助手',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 3),
            Text(
              '陪你读懂，也陪你想一想',
              style: TextStyle(fontSize: 10, color: Color(0xFFA4ADBA)),
            ),
          ],
        ),
      ),
      IconButton(
        key: const Key('assistant-close'),
        tooltip: '关闭阅读助手',
        iconSize: 18,
        color: const Color(0xFF8E96A3),
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.close),
      ),
    ],
  );

  Widget _contextChip() => Container(
    key: const Key('assistant-context'),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F7FB),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        const Icon(Icons.shield_outlined, size: 13, color: Color(0xFF8492A7)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '基于当前段落与已读章节 · 不涉及后文',
            style: const TextStyle(fontSize: 10, color: Color(0xFF8492A7)),
          ),
        ),
      ],
    ),
  );

  Widget _questionBubble() => Align(
    alignment: Alignment.centerRight,
    child: Container(
      key: const Key('assistant-question'),
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: const BoxDecoration(
        color: Color(0xFFEDF3FC),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(13),
          topRight: Radius.circular(13),
          bottomLeft: Radius.circular(13),
          bottomRight: Radius.circular(3),
        ),
      ),
      child: Text(
        _question,
        style: const TextStyle(fontSize: 12, color: Color(0xFF687B95)),
      ),
    ),
  );

  Widget _answerBlock() => Column(
    key: const Key('assistant-answer'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final line in _answer)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            line,
            style: const TextStyle(
              fontSize: 13,
              height: 1.95,
              color: Color(0xFF5D6878),
            ),
          ),
        ),
    ],
  );

  Widget _referenceChip() => Align(
    alignment: Alignment.centerLeft,
    child: InkWell(
      key: const Key('assistant-reference'),
      onTap: () => Navigator.of(context).maybePop(),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F9),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: 12,
              color: Color(0xFF7D8DA2),
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                '${widget.book.title} · ${widget.chapterTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFF7D8DA2)),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_outward, size: 12, color: Color(0xFF7D8DA2)),
          ],
        ),
      ),
    ),
  );

  Widget _answerActions() => Row(
    children: [
      IconButton(
        key: const Key('assistant-copy'),
        tooltip: '复制回答',
        iconSize: 16,
        constraints: const BoxConstraints.tightFor(width: 33, height: 33),
        padding: const EdgeInsets.all(7),
        color: const Color(0xFFA3ABB8),
        onPressed: _copyAnswer,
        icon: const Icon(Icons.copy_outlined),
      ),
      IconButton(
        key: const Key('assistant-save'),
        tooltip: '保存到笔记',
        iconSize: 16,
        constraints: const BoxConstraints.tightFor(width: 33, height: 33),
        padding: const EdgeInsets.all(7),
        color: const Color(0xFFA3ABB8),
        onPressed: _saveToNotes,
        icon: const Icon(Icons.bookmark_border),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          '只有本机内容 · 这本书共 ${widget.notes.length} 条笔记',
          key: const Key('assistant-note-count'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 9.5, color: Color(0xFFA3ABB8)),
        ),
      ),
    ],
  );

  Widget _suggestions() => Wrap(
    spacing: 7,
    runSpacing: 7,
    children: [
      _suggestion('帮我回顾已读内容', _AssistantMode.recap),
      _suggestion('解释这一段', _AssistantMode.explain),
      _suggestion('这一段值得留意什么', _AssistantMode.concept),
    ],
  );

  Widget _suggestion(String label, _AssistantMode mode) => InkWell(
    key: Key('assistant-suggestion-${mode.name}'),
    onTap: () => setState(() => _mode = mode),
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE4E9F1)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xFF8391A5)),
      ),
    ),
  );

  Widget _inputBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE4E8EE)),
      borderRadius: BorderRadius.circular(10),
      color: const Color(0xFFFBFCFE),
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('assistant-input'),
            controller: _input,
            style: const TextStyle(fontSize: 12, color: Color(0xFF4B586C)),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: '就这一段，再问一点…',
              hintStyle: TextStyle(fontSize: 12, color: Color(0xFFA9B2C0)),
            ),
            onSubmitted: _ask,
          ),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 31,
          height: 31,
          child: Material(
            color: const Color(0xFF6594DA),
            shape: const CircleBorder(),
            child: InkWell(
              key: const Key('assistant-send'),
              customBorder: const CircleBorder(),
              onTap: () => _ask(_input.text),
              child: const Icon(
                Icons.arrow_upward,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
