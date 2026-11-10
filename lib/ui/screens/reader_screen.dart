import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../application/app_controller.dart';
import '../../domain/book.dart';
import '../../domain/reader_settings.dart';
import '../../domain/reader_mark.dart';
import '../../domain/reading_activity.dart';
import '../../services/android_read_aloud.dart';
import '../../services/book_text_rules.dart';
import '../../services/book_text_search.dart';
import '../../services/read_aloud.dart';
import '../components/common.dart';
import '../components/design.dart';
import '../design_icons.dart';
import '../components/note_composer.dart';
import '../components/reader_cache_sheet.dart';
import '../components/reader_mark_sheet.dart';
import '../components/reader_marks_sheet.dart';
import '../components/reader_preferences.dart';
import '../components/reader_search_sheet.dart';
import '../components/reader_toc_sheet.dart';
import '../components/reading_assistant_sheet.dart';
import '../components/source_switch_sheet.dart';
import '../reader/reader_paginator.dart';
import '../reader/reader_palette.dart';
import '../reader/reader_paragraph.dart';
import '../theme.dart';
import 'audio_screen.dart';
import 'finish_screen.dart';
import 'notes_screen.dart';

/// 沉浸态 `.reader-head` 固定高度（与 CSS 一致）。
const double _immersiveHeadHeight = 36;

/// 工具顶栏 `.reader-tool-top` 大致占用（含少量内边距）。
const double _toolTopHeight = 48;

/// 沉浸页脚 + 底边距（10px 字高 + 29px 边距）。
const double _immersiveFooterReserve = 34;

/// 底栏工具区叠层占用的大致高度（进度条 + 四宫格 + 内边距）。
const double _toolBottomReserve = 168;

/// Space between the chapter title and the first line of body text.
const double _titleBodyGap = 16;

/// Keeps visible text and saved anchors tied to the current source binding.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.controller,
    required this.bookId,
    this.initialPosition,
    this.readAloud,
  });
  final AppController controller;
  final String bookId;
  final ReadingPosition? initialPosition;
  final ReadAloudController? readAloud;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  List<GlobalKey> _paragraphKeys = [];
  Chapter? _chapter;
  Chapter? _displayRaw;
  Chapter? _displayChapter;
  int _displayRulesRevision = -1;
  int _chapterIndex = 0;
  int _paragraphIndex = 0;
  int _requestedParagraphIndex = 0;
  int _generation = 0;
  String? _bindingSourceId;
  String? _bindingChapterId;
  bool _loading = true;
  bool _restoring = true;
  bool _leaving = false;
  bool _routePopped = false;
  bool? _pendingFinished;
  String? _error;
  String? _saveError;
  Timer? _saveTimer;
  Timer? _autoReadTimer;
  int? _autoReadSeconds;
  double _lastWidth = 0;
  double _lastFont = 0;
  double _lastHeight = 0;
  PageController? _pageController;
  ReaderPageLayout? _pageLayout;
  String? _pageLayoutKey;
  int _visiblePage = 0;
  bool _pagedFallback = false;
  // 进入阅读页默认沉浸式：只留紧凑标题与进度，点击正文中部再唤出工具栏。
  bool _chromeVisible = false;
  ReaderTheme? _dayTheme;
  ({int paragraphIndex, String text})? _selectedText;
  int? _scrollTapPointer;
  Offset? _scrollTapOrigin;
  Duration? _scrollTapStarted;
  final _recordedActivityKeys = <String>{};
  late final ReadAloudController _readAloud;
  late final bool _ownsReadAloud;

  AppController get controller => widget.controller;
  Book get book => controller.book(widget.bookId)!;

  Chapter _forDisplay(Chapter raw) {
    final revision = controller.textRulesRevision(widget.bookId);
    if (identical(_displayRaw, raw) &&
        _displayRulesRevision == revision &&
        _displayChapter != null) {
      return _displayChapter!;
    }
    _displayRaw = raw;
    _displayRulesRevision = revision;
    final rules = controller.textRules(widget.bookId);
    final paragraphs = BookTextRules.applyChapter(raw.paragraphs, rules);
    _displayChapter = identical(paragraphs, raw.paragraphs)
        ? raw
        : raw.withParagraphs(paragraphs);
    return _displayChapter!;
  }

  ({int paragraphIndex, String raw, String display})? _currentMarkTarget() {
    final rawChapter = _chapter;
    if (rawChapter == null || rawChapter.paragraphs.isEmpty) return null;
    final displayChapter = _forDisplay(rawChapter);
    final paragraphIndex = _visibleParagraph()
        .clamp(0, rawChapter.paragraphs.length - 1)
        .toInt();
    return (
      paragraphIndex: paragraphIndex,
      raw: rawChapter.paragraphs[paragraphIndex],
      display: displayChapter.paragraphs[paragraphIndex],
    );
  }

  Color _markColor(ReaderMarkColor color) => switch (color) {
    ReaderMarkColor.amber => const Color(0xFFF3D77A),
    ReaderMarkColor.mint => const Color(0xFF9AD7BE),
    ReaderMarkColor.blue => const Color(0xFFAFCBEE),
  };

  bool get _hasActiveDisplayRules =>
      controller.textRules(widget.bookId).any((rule) => rule.enabled);

  /// 选中文字时可以直接请求本机回顾：它只读已缓存正文与已有笔记，
  /// 所以不需要联网，也不受显示替换规则影响。
  bool get _canExplainSelection => _selectedText != null && _chapter != null;

  bool get _canMarkSelectedText =>
      _selectedText != null &&
      _chapter != null &&
      controller.settings.flow == ReaderFlow.scrolling &&
      !_hasActiveDisplayRules;

  void _onParagraphSelection(int paragraphIndex, String? text) {
    if (text == null || text.isEmpty) {
      if (_selectedText != null) setState(() => _selectedText = null);
      return;
    }
    if (_chapter == null ||
        controller.settings.flow != ReaderFlow.scrolling ||
        _hasActiveDisplayRules ||
        paragraphIndex < 0 ||
        paragraphIndex >= _chapter!.paragraphs.length) {
      return;
    }
    final raw = _chapter!.paragraphs[paragraphIndex];
    if (!ReaderMark.hasUniqueOccurrence(raw, text)) return;
    final selected = _selectedText;
    if (selected != null &&
        selected.paragraphIndex == paragraphIndex &&
        selected.text == text) {
      return;
    }
    setState(
      () => _selectedText = (paragraphIndex: paragraphIndex, text: text),
    );
  }

  List<ReaderTextHighlight> _rangeHighlights(
    int paragraphIndex,
    String rawParagraph,
  ) => [
    for (final mark in controller.readerRangeMarksAt(
      widget.bookId,
      _chapterIndex,
      paragraphIndex,
      rawParagraph,
    ))
      ReaderTextHighlight(
        text: mark.selectedText!,
        color: _markColor(mark.color),
      ),
  ];

  Widget _markedParagraph(
    int paragraphIndex,
    String rawParagraph,
    Widget child,
  ) {
    final mark = controller.readerMarkAt(
      widget.bookId,
      _chapterIndex,
      paragraphIndex,
      rawParagraph,
    );
    if (mark == null) return child;
    return Semantics(
      container: true,
      label: '段落标注',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _markColor(mark.color).withValues(alpha: .26),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: child,
        ),
      ),
    );
  }

  void _showMarkSheet() {
    final target = _currentMarkTarget();
    if (target == null) {
      showMessage(context, '当前没有可标注的段落。');
      return;
    }
    final existing = controller.readerMarkAt(
      widget.bookId,
      _chapterIndex,
      target.paragraphIndex,
      target.raw,
    );
    final preview = target.display.length <= 1200
        ? target.display
        : '${target.display.substring(0, 1200)}…';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _readerSheetColor,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => Theme(
        data: _readerSheetTheme(),
        child: ReaderMarkSheet(
          paragraph: preview,
          mark: existing,
          onSave: (color, note) => controller.addReaderMark(
            widget.bookId,
            _chapterIndex,
            target.paragraphIndex,
            color: color,
            note: note,
          ),
          onDelete: existing == null
              ? null
              : () => controller.deleteReaderMark(existing.id),
        ),
      ),
    );
  }

  void _showSelectedTextMarkSheet() {
    final selected = _selectedText;
    final rawChapter = _chapter;
    if (selected == null ||
        rawChapter == null ||
        controller.settings.flow != ReaderFlow.scrolling ||
        _hasActiveDisplayRules ||
        selected.paragraphIndex < 0 ||
        selected.paragraphIndex >= rawChapter.paragraphs.length) {
      showMessage(context, '当前没有可标注的唯一选中文字。');
      return;
    }
    final raw = rawChapter.paragraphs[selected.paragraphIndex];
    if (!ReaderMark.hasUniqueOccurrence(raw, selected.text)) {
      showMessage(context, '选中文字已变化或在段落中不唯一。');
      return;
    }
    ReaderMark? existing;
    for (final mark in controller.readerRangeMarksAt(
      widget.bookId,
      _chapterIndex,
      selected.paragraphIndex,
      raw,
    )) {
      if (mark.selectedText == selected.text) {
        existing = mark;
        break;
      }
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _readerSheetColor,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => Theme(
        data: _readerSheetTheme(),
        child: ReaderMarkSheet(
          paragraph: selected.text,
          isSelectedText: true,
          mark: existing,
          onSave: (color, note) async {
            final mark = await controller.addReaderMark(
              widget.bookId,
              _chapterIndex,
              selected.paragraphIndex,
              color: color,
              note: note,
              selectedText: selected.text,
            );
            if (mounted) setState(() => _selectedText = null);
            return mark;
          },
          onDelete: existing == null
              ? null
              : () async {
                  await controller.deleteReaderMark(existing!.id);
                  if (mounted) setState(() => _selectedText = null);
                },
        ),
      ),
    );
  }

  Future<void> _showMarkManager() async {
    final location = await showModalBottomSheet<ReaderMarkLocation>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _readerSheetColor,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheetContext) => Theme(
        data: _readerSheetTheme(),
        child: ReaderMarksSheet(
          controller: controller,
          bookId: widget.bookId,
          onOpen: (target) => Navigator.pop(sheetContext, target),
        ),
      ),
    );
    if (!mounted || location == null) return;
    await _jump(location.chapterIndex, location.paragraphIndex);
  }

  @override
  void initState() {
    super.initState();
    _ownsReadAloud = widget.readAloud == null;
    final supported = AndroidReadAloudEngine.isSupported;
    _readAloud =
        widget.readAloud ??
        ReadAloudController(
          engine: supported ? AndroidReadAloudEngine() : null,
          supported: supported,
        );
    _readAloud.addListener(_onReadAloudChanged);
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    final position = widget.initialPosition ?? book.position;
    _load(
      position.chapterIndex.clamp(0, book.chapters.length - 1),
      position.paragraphIndex,
    );
  }

  void _onReadAloudChanged() {
    if (mounted) setState(() {});
  }

  // A source switch can replace the binding without starting this view's load.
  bool _matchesBinding(Book current) =>
      current.sourceId == _bindingSourceId &&
      _chapterIndex >= 0 &&
      _chapterIndex < current.chapters.length &&
      current.chapters[_chapterIndex].id == _bindingChapterId;

  bool _canUseLoad(int generation) {
    if (!mounted || generation != _generation) return false;
    final current = controller.book(widget.bookId);
    return current != null && _matchesBinding(current);
  }

  void _recordChapterActivity(int generation, Book current, int index) {
    if (!_canUseLoad(generation) ||
        index < 0 ||
        index >= current.chapters.length) {
      return;
    }
    final key = '${current.sourceId}::${current.chapters[index].id}';
    if (!_recordedActivityKeys.add(key)) return;
    final kind = _recordedActivityKeys.length == 1
        ? ReadingActivityKind.opened
        : ReadingActivityKind.chapter;
    unawaited(() async {
      try {
        await controller.recordReadingActivity(
          widget.bookId,
          index,
          kind: kind,
        );
      } catch (_) {
        _recordedActivityKeys.remove(key);
      }
    }());
  }

  void _scheduleRestore(int anchor) {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canUseLoad(generation)) _restore(anchor);
    });
  }

  void _scheduleBindingReload() {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      final current = controller.book(widget.bookId);
      if (current == null ||
          current.chapters.isEmpty ||
          _matchesBinding(current)) {
        return;
      }
      _pendingFinished = null;
      unawaited(
        _load(
          current.position.chapterIndex.clamp(0, current.chapters.length - 1),
          current.position.paragraphIndex,
        ),
      );
    });
  }

  Future<void> _load(int index, int paragraph) async {
    // 较早发起的请求可能较晚完成，不能覆盖用户后来选择的章节。
    final generation = ++_generation;
    final current = book;
    _saveTimer?.cancel();
    setState(() {
      _bindingSourceId = current.sourceId;
      _bindingChapterId = index >= 0 && index < current.chapters.length
          ? current.chapters[index].id
          : null;
      _loading = true;
      _restoring = true;
      _error = null;
      _chapterIndex = index;
      _requestedParagraphIndex = paragraph;
      _chapter = null;
      _displayRaw = null;
      _displayChapter = null;
      _displayRulesRevision = -1;
      _pageLayout = null;
      _pageLayoutKey = null;
      _selectedText = null;
    });
    try {
      final chapter = await controller.chapter(widget.bookId, index);
      if (!_canUseLoad(generation)) return;
      setState(() {
        _chapter = chapter;
        _loading = false;
        _paragraphIndex = paragraph.clamp(0, chapter.paragraphs.length - 1);
        _paragraphKeys = List.generate(
          chapter.paragraphs.length,
          (_) => GlobalKey(),
        );
      });
      _recordChapterActivity(generation, current, index);
      // 段落偏移依赖本轮布局；字号或视口变化后也要重新定位。
      _scheduleRestore(_paragraphIndex);
    } catch (error) {
      if (_canUseLoad(generation)) {
        _stopAutoRead();
        setState(() {
          _loading = false;
          _error = errorMessage(error);
          _chromeVisible = true;
        });
      }
    }
  }

  void _restore(int index) {
    if (!mounted || _chapter == null) return;
    if (controller.settings.flow == ReaderFlow.paged && !_pagedFallback) {
      _paragraphIndex = index;
      _restoring = false;
      unawaited(_persist());
      return;
    }
    if (!_scroll.hasClients) return;
    final target = _paragraphKeys[index.clamp(0, _paragraphKeys.length - 1)]
        .currentContext
        ?.findRenderObject();
    if (index == 0) {
      _scroll.jumpTo(0);
    } else if (target != null) {
      final offset = RenderAbstractViewport.of(
        target,
      ).getOffsetToReveal(target, 0).offset;
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
    }
    _paragraphIndex = index;
    _restoring = false;
    unawaited(_persist());
  }

  int _visibleParagraph() {
    if (controller.settings.flow == ReaderFlow.paged && !_pagedFallback) {
      return _paragraphIndex;
    }
    if (_restoring || !_scroll.hasClients) return _paragraphIndex;
    var visible = 0;
    for (var index = 0; index < _paragraphKeys.length; index++) {
      final target = _paragraphKeys[index].currentContext?.findRenderObject();
      if (target == null) continue;
      final offset = RenderAbstractViewport.of(
        target,
      ).getOffsetToReveal(target, 0).offset;
      if (offset <= _scroll.offset + 12) {
        visible = index;
      } else {
        break;
      }
    }
    return visible;
  }

  void _onScroll() {
    if (_loading || _restoring) return;
    _paragraphIndex = _visibleParagraph();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _persist);
  }

  ReadingPosition get _currentPosition => ReadingPosition(
    chapterIndex: _chapterIndex,
    paragraphIndex: _paragraphIndex,
  );

  Future<bool> _persist({bool? finished}) async {
    _saveTimer?.cancel();
    final current = controller.book(widget.bookId);
    if (current == null || !_matchesBinding(current)) return false;
    final generation = _generation;
    // 完成标记失败后，重试和自动保存都必须保留原操作意图。
    if (finished != null) _pendingFinished = finished;
    if (_chapter == null || _loading) return _pendingFinished == null;
    final pendingFinished = _pendingFinished;
    try {
      await controller.savePosition(
        widget.bookId,
        _currentPosition,
        finished: pendingFinished,
      );
      if (!_canUseLoad(generation)) return false;
      if (_pendingFinished == pendingFinished) _pendingFinished = null;
      if (mounted && _saveError != null) setState(() => _saveError = null);
      return true;
    } catch (_) {
      if (_canUseLoad(generation)) {
        setState(() => _saveError = '阅读进度暂未保存，请检查本机存储空间。');
      }
      return false;
    }
  }

  Future<void> _retrySave() async {
    await _persist();
  }

  void _popReader() {
    // 路由退出动画期间仍然 mounted；迟到的保存完成不能再次弹出书架。
    if (!mounted || _routePopped) return;
    _routePopped = true;
    Navigator.of(context).pop();
  }

  void _discardAndLeave() {
    _leaving = true;
    _popReader();
  }

  Future<void> _markFinished() async {
    if (_loading || _chapter == null) return;
    if (await _persist(finished: true) && mounted) {
      try {
        await controller.recordReadingActivity(
          widget.bookId,
          _chapterIndex,
          kind: ReadingActivityKind.finished,
        );
      } catch (_) {
        // Reading completion remains saved even if optional local history fails.
      }
      if (!mounted) return;
      final finishedBook = book;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FinishScreen(
            controller: controller,
            book: finishedBook,
            onShelf: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            onOpenNote: (note) {
              Navigator.of(context).pop();
              unawaited(_jump(note.chapterIndex, note.paragraphIndex));
            },
          ),
        ),
      );
    }
  }

  void _openAudio() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AudioScreen(
          controller: controller,
          book: book,
          chapterIndex: _chapterIndex,
          readAloud: _readAloud,
          onChapterChanged: (index) {
            Navigator.of(context).pop();
            unawaited(_jump(index));
          },
          onOpenToc: () {
            Navigator.of(context).pop();
            _showToc();
          },
        ),
      ),
    );
  }

  Future<void> _jump(int chapterIndex, [int paragraph = 0]) async {
    if (_loading) return;
    unawaited(_readAloud.stop());
    if (!await _persist()) return;
    if (mounted) await _load(chapterIndex, paragraph);
  }

  Future<void> _leave() async {
    if (_leaving || _routePopped) return;
    _stopAutoRead();
    unawaited(_readAloud.stop());
    _leaving = true;
    if (await _persist()) {
      _popReader();
    } else {
      _leaving = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopAutoRead();
      unawaited(_readAloud.stop());
      unawaited(_persist());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readAloud.removeListener(_onReadAloudChanged);
    if (_ownsReadAloud) {
      _readAloud.dispose();
    } else {
      unawaited(_readAloud.stop());
    }
    _saveTimer?.cancel();
    _autoReadTimer?.cancel();
    _scroll.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _clearScrollTap() {
    _scrollTapPointer = null;
    _scrollTapOrigin = null;
    _scrollTapStarted = null;
  }

  Widget _buildScrollingChapter({
    required double width,
    required Chapter chapter,
    required ReaderSettings settings,
    required Color ink,
    required Color muted,
  }) => Listener(
    // Scroll and text selection keep their gestures; only a short central tap toggles tools.
    onPointerDown: (event) {
      final x = event.localPosition.dx;
      if (x < width / 3 || x > width * 2 / 3) {
        _clearScrollTap();
        return;
      }
      _scrollTapPointer = event.pointer;
      _scrollTapOrigin = event.localPosition;
      _scrollTapStarted = event.timeStamp;
    },
    onPointerMove: (event) {
      if (event.pointer == _scrollTapPointer &&
          (event.localPosition - _scrollTapOrigin!).distance > 12) {
        _clearScrollTap();
      }
    },
    onPointerUp: (event) {
      final elapsed = _scrollTapStarted == null
          ? null
          : event.timeStamp - _scrollTapStarted!;
      final tapped =
          event.pointer == _scrollTapPointer &&
          elapsed != null &&
          elapsed >= Duration.zero &&
          elapsed <= const Duration(milliseconds: 300) &&
          (event.localPosition - _scrollTapOrigin!).distance <= 12;
      _clearScrollTap();
      if (tapped) _toggleChrome();
    },
    onPointerCancel: (event) {
      if (event.pointer == _scrollTapPointer) _clearScrollTap();
    },
    child: Builder(
      builder: (context) {
        final insets = _readerContentInsets(context, width);
        return SingleChildScrollView(
          key: const Key('reader-scrolling-view'),
          controller: _scroll,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  insets.horizontal,
                  insets.top,
                  insets.horizontal,
                  insets.bottom + 56,
                ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapter.title,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  book.isExcerpt ? '公版原文节选 · 已保存在本机' : '本章已缓存 · 可离线阅读',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 36),
                for (var index = 0; index < chapter.paragraphs.length; index++)
                  Padding(
                    key: _paragraphKeys[index],
                    padding: EdgeInsets.only(bottom: settings.paragraphSpacing),
                    child: _markedParagraph(
                      index,
                      _chapter!.paragraphs[index],
                      ReaderParagraph(
                        text: chapter.paragraphs[index],
                        indent: index != 0,
                        selectable: !_hasActiveDisplayRules,
                        highlights: _hasActiveDisplayRules
                            ? const []
                            : _rangeHighlights(
                                index,
                                _chapter!.paragraphs[index],
                              ),
                        onSelectionChanged: _hasActiveDisplayRules
                            ? null
                            : (text) => _onParagraphSelection(index, text),
                        style: TextStyle(
                          inherit: false,
                          fontWeight: settings.boldText
                              ? FontWeight.bold
                              : FontWeight.w400,
                          fontFamily: 'NotoSansSC',
                          fontSize: settings.fontSize,
                          height: settings.lineHeight,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    _chapterIndex + 1 == book.chapters.length
                        ? (book.isExcerpt ? '本书节选至此，感谢阅读。' : '全文完。')
                        : '本章结束，继续下一章。',
                    style: TextStyle(fontSize: 13, color: muted),
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
  );

  Future<void> _turnPage(int delta, int pageCount) async {
    final pages = _pageController;
    if (_loading ||
        _restoring ||
        pages == null ||
        !pages.hasClients ||
        pages.position.isScrollingNotifier.value) {
      return;
    }
    final target = ((pages.page ?? 0).round() + delta).clamp(0, pageCount - 1);
    await pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  /// 进度滑条跳到本章第 [contentPage] 页（从 0 起）。
  Future<void> _goToPage(int contentPage) async {
    final pages = _pageController;
    final layout = _pageLayout;
    if (_loading ||
        _restoring ||
        pages == null ||
        layout == null ||
        !pages.hasClients) {
      return;
    }
    final target = contentPage.clamp(0, layout.pages.length - 1);
    if (_visiblePage == target) return;
    final leading = _chapterIndex > 0 ? 1 : 0;
    await pages.animateToPage(
      leading + target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  bool get _autoReadActive => _autoReadTimer != null;

  bool get _canStartAutoRead =>
      !_loading &&
      !_restoring &&
      controller.settings.flow == ReaderFlow.paged &&
      !_pagedFallback &&
      _pageLayout != null;

  void _showAutoReadControls() {
    if (!_autoReadActive && !_canStartAutoRead) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Text('自动翻页'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _autoReadActive
                      ? '当前每 ${_autoReadSeconds!} 秒翻一页。到最后一页、离开读者或切换滚动阅读时会停止。'
                      : '只在分页阅读中可用。到最后一页、离开读者或切换滚动阅读时会停止。',
                  style: const TextStyle(color: AppColors.muted, height: 1.7),
                ),
                const SizedBox(height: 12),
                if (_autoReadActive)
                  ListTile(
                    key: const Key('reader-auto-read-stop'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(DesignIcons.pause),
                    title: const Text('停止自动翻页'),
                    onTap: () {
                      _stopAutoRead();
                      Navigator.pop(dialogContext);
                    },
                  )
                else
                  for (final seconds in [5, 10, 20])
                    ListTile(
                      key: Key('reader-auto-read-$seconds'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(DesignIcons.timer),
                      title: Text('$seconds 秒 / 页'),
                      onTap: () {
                        _startAutoRead(seconds);
                        Navigator.pop(dialogContext);
                      },
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startAutoRead(int seconds) {
    if (seconds <= 0 ||
        _loading ||
        _restoring ||
        controller.settings.flow != ReaderFlow.paged ||
        _pagedFallback) {
      return;
    }
    _autoReadTimer?.cancel();
    setState(() => _autoReadSeconds = seconds);
    _autoReadTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      unawaited(_advanceAutoRead());
    });
  }

  void _stopAutoRead({bool notify = true}) {
    _autoReadTimer?.cancel();
    _autoReadTimer = null;
    if (_autoReadSeconds == null) return;
    if (notify && mounted) {
      setState(() => _autoReadSeconds = null);
    } else {
      _autoReadSeconds = null;
    }
  }

  Future<void> _advanceAutoRead() async {
    if (!mounted ||
        !_autoReadActive ||
        _loading ||
        _restoring ||
        controller.settings.flow != ReaderFlow.paged ||
        _pagedFallback) {
      _stopAutoRead();
      return;
    }
    final layout = _pageLayout;
    final pages = _pageController;
    if (layout == null || pages == null || !pages.hasClients) return;
    final hasPrevious = _chapterIndex > 0;
    final hasNext = _chapterIndex + 1 < book.chapters.length;
    final itemCount =
        layout.pages.length + (hasPrevious ? 1 : 0) + (hasNext ? 1 : 0);
    final currentPage = (pages.page ?? 0).round();
    if (!hasNext && currentPage >= itemCount - 1) {
      _stopAutoRead();
      return;
    }
    await _turnPage(1, itemCount);
  }

  void _toggleChrome() => setState(() {
    _chromeVisible = !_chromeVisible;
    _pageLayoutKey = null;
  });

  /// 设计稿 `reader-footer` 右侧：`进度% · 页/总页`；顶部已有章名时不重复展示。
  double _liveReadingProgress(ReaderSettings settings) {
    final chapters = book.chapters.length;
    if (chapters == 0) return book.progress;
    if (book.finished) return 1;
    final inChapter = settings.flow == ReaderFlow.paged &&
            !_pagedFallback &&
            _pageLayout != null
        ? (_visiblePage + 1) / math.max(1, _pageLayout!.pages.length)
        : () {
            final count = _chapter?.paragraphs.length ?? 0;
            if (count == 0) return 0.0;
            return _visibleParagraph() / count;
          }();
    return ((_chapterIndex + inChapter.clamp(0, 1)) / chapters).clamp(0, 1);
  }

  /// 浮层不占 AppBar 后，分页必须按顶/底叠层预留高度，否则会与正文抢同一行。
  ({double top, double bottom, double horizontal}) _readerContentInsets(
    BuildContext context,
    double width,
  ) {
    final safe = MediaQuery.paddingOf(context);
    final horizontal = width < 650 ? 29.0 : 48.0;
    if (_chromeVisible) {
      return (
        top: safe.top + _toolTopHeight,
        bottom: safe.bottom + _toolBottomReserve,
        horizontal: horizontal,
      );
    }
    return (
      top: safe.top + _immersiveHeadHeight,
      bottom: safe.bottom + _immersiveFooterReserve,
      horizontal: horizontal,
    );
  }

  String _immersiveFooterLabel(ReaderSettings settings) {
    final percent = (_liveReadingProgress(settings) * 100).round();
    if (settings.flow == ReaderFlow.paged && !_pagedFallback) {
      final pages = math.max(1, _pageLayout?.pages.length ?? 1);
      final page = (_visiblePage + 1).clamp(1, pages);
      return '$percent% · $page/$pages';
    }
    return '$percent% · 滚动';
  }

  Color get _readerSheetColor =>
      ReaderPalette.of(controller.settings.theme).background;

  /// 阅读弹层跟当前阅读底色走，图标和文字用同一套墨色。
  ThemeData _readerSheetTheme() {
    final palette = ReaderPalette.of(controller.settings.theme);
    final base = appTheme();
    return base.copyWith(
      scaffoldBackgroundColor: palette.background,
      iconTheme: IconThemeData(color: palette.ink),
      dividerTheme: DividerThemeData(
        color: palette.ink.withValues(alpha: .12),
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.ink,
        textColor: palette.ink,
        subtitleTextStyle: TextStyle(color: palette.muted, fontSize: 12),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: palette.ink,
        displayColor: palette.ink,
      ),
      extensions: <ThemeExtension<dynamic>>[
        ChromeColors(
          ink: palette.ink,
          muted: palette.muted,
          surface: palette.background,
        ),
      ],
    );
  }

  /// 设计稿 `reader-more`：离线/换源/搜索/笔记/读完等；自动翻页与标注等不在「阅读设置」里。
  List<Widget> _readerAuxiliaryToolRows(BuildContext sheetContext) => [
        const SectionLabel('辅助能力'),
        ListTile(
          key: const Key('reader-auto-read'),
          contentPadding: EdgeInsets.zero,
          title: const Text('自动翻页'),
          subtitle: Text(
            _autoReadActive ? '当前每 ${_autoReadSeconds!} 秒翻一页' : '仅支持分页阅读',
          ),
          trailing: Icon(
            _autoReadActive
                ? DesignIcons.pause
                : DesignIcons.timer,
          ),
          enabled: _autoReadActive || _canStartAutoRead,
          onTap: _autoReadActive || _canStartAutoRead
              ? () {
                  Navigator.pop(sheetContext);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showAutoReadControls();
                  });
                }
              : null,
        ),
        ListTile(
          key: const Key('reader-read-aloud'),
          contentPadding: EdgeInsets.zero,
          title: const Text('设备朗读'),
          subtitle: Text(
            _readAloud.isSpeaking
                ? '正在朗读当前章节'
                : (_readAloud.isSupported
                      ? '使用设备已安装的中文语音'
                      : '仅 Android 设备可用'),
          ),
          trailing: Icon(
            _readAloud.isSpeaking
                ? DesignIcons.stopCircle
                : DesignIcons.volume,
          ),
          onTap: () {
            Navigator.pop(sheetContext);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _openAudio();
            });
          },
        ),
        ListTile(
          key: const Key('reader-mark'),
          contentPadding: EdgeInsets.zero,
          title: const Text('段落标注'),
          subtitle: const Text('标注当前显示段落，可添加本地备注'),
          trailing: const Icon(DesignIcons.highlighter),
          onTap: () {
            Navigator.pop(sheetContext);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showMarkSheet();
            });
          },
        ),
        ListTile(
          key: const Key('reader-selected-text-mark'),
          contentPadding: EdgeInsets.zero,
          title: const Text('选中文字标注'),
          subtitle: Text(
            _hasActiveDisplayRules
                ? '正文显示替换启用时不可使用'
                : controller.settings.flow != ReaderFlow.scrolling
                ? '切换到上下滚动后可选择文字'
                : _canMarkSelectedText
                ? '已选择唯一文字片段'
                : '长按并拖动选择当前段落文字',
          ),
          trailing: const Icon(DesignIcons.type),
          enabled: _canMarkSelectedText,
          onTap: !_canMarkSelectedText
              ? null
              : () {
                  Navigator.pop(sheetContext);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showSelectedTextMarkSheet();
                  });
                },
        ),
        ListTile(
          key: const Key('reader-selected-explain'),
          contentPadding: EdgeInsets.zero,
          title: const Text('解释这段文字'),
          subtitle: Text(
            _canExplainSelection
                ? '用本机已读内容回顾这一段，不连接模型'
                : controller.settings.flow != ReaderFlow.scrolling
                ? '切换到上下滚动后可选择文字'
                : '长按并拖动选择当前段落文字',
          ),
          trailing: const Icon(DesignIcons.sparkles),
          enabled: _canExplainSelection,
          onTap: !_canExplainSelection
              ? null
              : () {
                  Navigator.pop(sheetContext);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _openSelectionAssistant();
                  });
                },
        ),
        ListTile(
          key: const Key('reader-mark-manager'),
          contentPadding: EdgeInsets.zero,
          title: const Text('段落标注管理'),
          subtitle: Text(
            '本书已保存 ${controller.readerMarks(widget.bookId).length} 条本地标注',
          ),
          trailing: const Icon(DesignIcons.bookmark),
          onTap: () {
            Navigator.pop(sheetContext);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_showMarkManager());
            });
          },
        ),
      ];

  void _showReaderMoreSheet() {
    final dark = ReaderPalette.of(controller.settings.theme).isDark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _readerSheetColor,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheetContext) => Theme(
        data: _readerSheetTheme(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 0, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '阅读工具',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: ReaderPalette.of(
                            controller.settings.theme,
                          ).ink,
                        ),
                      ),
                    ),
                    CircleIconButton(
                      icon: DesignIcons.close,
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
              if (book.isRemote)
                ListRow(
                  icon: DesignIcons.sheetDownload,
                  title: '离线阅读',
                  subtitle: '下载后，没有网络也能读',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        backgroundColor: _readerSheetColor,
                        constraints: const BoxConstraints(maxWidth: 600),
                        builder: (_) => Theme(
                          data: _readerSheetTheme(),
                          child: ReaderCacheSheet(
                            controller: controller,
                            book: book,
                          ),
                        ),
                      );
                    });
                  },
                ),
              if (book.isRemote)
                ListRow(
                  icon: DesignIcons.toolSource,
                  title: '更换来源',
                  subtitle: '保留进度，重新匹配章节',
                  onTap: _loading
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) unawaited(_changeSource());
                          });
                        },
                ),
              KeyedSubtree(
                key: const Key('reader-search'),
                child: ListRow(
                  icon: DesignIcons.sheetSearch,
                  title: '搜索已下载内容',
                  onTap: _chapter == null
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) unawaited(_showSearch());
                          });
                        },
                ),
              ),
              KeyedSubtree(
                key: const Key('reader-tool-notes'),
                child: ListRow(
                  icon: DesignIcons.toolNotes,
                  title: '读书笔记',
                  subtitle: '查看本书的想法与划线',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _openNotes(book);
                    });
                  },
                ),
              ),
              ListRow(
                icon: DesignIcons.selectionHighlight,
                title: '选择文字与写笔记',
                subtitle: controller.settings.flow == ReaderFlow.scrolling
                    ? null
                    : '切换到上下滚动后可选择文字',
                onTap: controller.settings.flow == ReaderFlow.scrolling
                    ? () {
                        Navigator.pop(sheetContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) showMessage(context, '长按正文选择文字。');
                        });
                      }
                    : null,
              ),
              ListRow(
                icon: DesignIcons.sheetMarkDone,
                title: '标记为已读完',
                onTap: book.finished
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) unawaited(_markFinished());
                        });
                      },
              ),
              KeyedSubtree(
                key: const Key('reader-tool-theme'),
                child: ListRow(
                  icon: dark
                      ? DesignIcons.sun
                      : DesignIcons.moon,
                  title: dark ? '切换到日间' : '切换到夜间',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) unawaited(_toggleTheme());
                    });
                  },
                ),
              ),
              ..._readerAuxiliaryToolRows(sheetContext),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleTheme() async {
    final currentTheme = controller.settings.theme;
    if (currentTheme != ReaderTheme.dark) _dayTheme = currentTheme;
    final nextTheme = currentTheme == ReaderTheme.dark
        ? (_dayTheme ?? ReaderTheme.paper)
        : ReaderTheme.dark;
    try {
      await _updateReaderSettings(
        controller.settings.copyWith(theme: nextTheme),
      );
    } catch (error) {
      if (mounted) showMessage(context, '阅读主题未保存：${errorMessage(error)}');
    }
  }

  Widget _buildPagedChapter({
    required Chapter chapter,
    required ReaderSettings settings,
    required Color ink,
    required Color muted,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final insets = _readerContentInsets(context, constraints.maxWidth);
      final horizontalPadding = insets.horizontal;
      final contentWidth = math.max(
        1.0,
        math.min(760.0, constraints.maxWidth) - horizontalPadding * 2,
      );

      final contentHeight = math.max(
        1.0,
        constraints.maxHeight - insets.top - insets.bottom,
      );
      final bodyStyle = TextStyle(
        inherit: false,
        fontFamily: 'NotoSansSC',
        fontSize: settings.fontSize,
        fontWeight: settings.boldText ? FontWeight.bold : FontWeight.w400,
        height: settings.lineHeight,
        color: ink,
      );
      final titleStyle = TextStyle(
        inherit: false,
        fontFamily: 'NotoSansSC',
        fontSize: 26,
        height: 1.6,
        fontWeight: FontWeight.w600,
        color: ink,
      );
      final titleMeasurement = TextPainter(
        text: TextSpan(text: chapter.title, style: titleStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: contentWidth);
      final minimumHeight =
          titleMeasurement.height +
          _titleBodyGap +
          settings.fontSize * settings.lineHeight;
      titleMeasurement.dispose();
      // Landscape and large accessibility text must remain readable, not crash.
      if (contentHeight < minimumHeight) {
        if (!_pagedFallback) {
          _pagedFallback = true;
          _scheduleRestore(_paragraphIndex);
        }
        return _buildScrollingChapter(
          width: constraints.maxWidth,
          chapter: chapter,
          settings: settings,
          ink: ink,
          muted: muted,
        );
      }
      if (_pagedFallback) _pageLayoutKey = null;
      _pagedFallback = false;
      final layoutKey =
          '${chapter.id}|$_displayRulesRevision|$_chromeVisible|'
          '${contentWidth.toStringAsFixed(1)}|${contentHeight.toStringAsFixed(1)}|'
          '${settings.fontSize}|${settings.lineHeight}|'
          '${settings.paragraphSpacing}|${settings.boldText}';
      if (_pageLayoutKey != layoutKey || _pageLayout == null) {
        final layout = ReaderPaginator.paginate(
          title: chapter.title,
          paragraphs: chapter.paragraphs,
          maxWidth: contentWidth,
          maxHeight: contentHeight,
          bodyStyle: bodyStyle,
          titleStyle: titleStyle,
          firstPageChromeHeight: _titleBodyGap,
          paragraphSpacing: settings.paragraphSpacing,
        );
        final leading = _chapterIndex > 0 ? 1 : 0;
        final contentPage = layout.pageForParagraph(_paragraphIndex);
        final oldController = _pageController;
        _pageController = PageController(initialPage: leading + contentPage);
        _pageLayout = layout;
        _pageLayoutKey = layoutKey;
        _visiblePage = contentPage;
        if (oldController != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => oldController.dispose(),
          );
        }
      }

      final layout = _pageLayout!;
      final pageController = _pageController!;
      final hasPrevious = _chapterIndex > 0;
      final hasNext = _chapterIndex + 1 < book.chapters.length;
      final leading = hasPrevious ? 1 : 0;
      final itemCount = layout.pages.length + leading + (hasNext ? 1 : 0);
      return Stack(
        children: [
          PageView.builder(
            key: const Key('reader-paged-view'),
            controller: pageController,
            itemCount: itemCount,
            onPageChanged: (index) {
              if (_loading || _restoring) return;
              if (hasPrevious && index == 0) {
                unawaited(_jump(_chapterIndex - 1));
                return;
              }
              final contentIndex = index - leading;
              if (hasNext && contentIndex == layout.pages.length) {
                unawaited(_jump(_chapterIndex + 1));
                return;
              }
              if (contentIndex < 0 || contentIndex >= layout.pages.length) {
                return;
              }
              final anchor = layout.pages[contentIndex].anchorParagraphIndex;
              if (_visiblePage != contentIndex || _paragraphIndex != anchor) {
                setState(() {
                  _visiblePage = contentIndex;
                  _paragraphIndex = anchor;
                });
              }
              _saveTimer?.cancel();
              _saveTimer = Timer(const Duration(milliseconds: 500), _persist);
            },
            itemBuilder: (context, index) {
              if (hasPrevious && index == 0) {
                return const Center(child: Text('正在打开上一章…'));
              }
              final contentIndex = index - leading;
              if (hasNext && contentIndex == layout.pages.length) {
                return const Center(child: Text('正在打开下一章…'));
              }
              final page = layout.pages[contentIndex];
              return Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          insets.top,
                          horizontalPadding,
                          insets.bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (page.showsChapterHeader) ...[
                              Text(
                                chapter.title,
                                style: titleStyle,
                                textScaler: TextScaler.noScaling,
                              ),
                              const SizedBox(height: _titleBodyGap),
                            ],
                            for (final fragment in page.fragments)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: fragment.trailingSpacing,
                                ),
                                child: _markedParagraph(
                                  fragment.paragraphIndex,
                                  _chapter!.paragraphs[fragment.paragraphIndex],
                                  ReaderParagraph(
                                    text: fragment.text,
                                    isContinuation: fragment.isContinuation,
                                    indent: fragment.indent,
                                    style: bodyStyle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (final direction in [-1, 0, 1])
                          Expanded(
                            child: direction == 0
                                ? Semantics(
                                    label: _chromeVisible
                                        ? '收起阅读工具栏'
                                        : '显示阅读工具栏',
                                    button: true,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _toggleChrome,
                                      child: const SizedBox.expand(),
                                    ),
                                  )
                                : Semantics(
                                    label: direction < 0 ? '上一页' : '下一页',
                                    button: true,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => unawaited(
                                        _turnPage(direction, itemCount),
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          Offstage(
            child: Text(
              '${_visiblePage + 1}/${layout.pages.length}',
              key: const Key('reader-page-indicator'),
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final settings = controller.settings;
      final current = controller.book(widget.bookId);
      final bindingChanged =
          current != null &&
          current.chapters.isNotEmpty &&
          !_matchesBinding(current);
      if (bindingChanged) _scheduleBindingReload();
      final nextDisabled =
          _loading ||
          bindingChanged ||
          (_chapter == null && _chapterIndex + 1 == book.chapters.length);
      final palette = ReaderPalette.of(settings.theme);
      final dark = palette.isDark;
      final background = palette.background;
      final ink = palette.ink;
      final muted = palette.muted;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Theme(
          data: Theme.of(context).copyWith(
            brightness: dark ? Brightness.dark : Brightness.light,
            iconTheme: IconThemeData(color: ink),
          ),
          child: Scaffold(
            backgroundColor: background,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final rulesChanged =
                    _displayRulesRevision >= 0 &&
                    _displayRulesRevision !=
                        controller.textRulesRevision(widget.bookId);
                final changed =
                    _lastWidth != constraints.maxWidth ||
                    _lastFont != settings.fontSize ||
                    _lastHeight != settings.lineHeight ||
                    rulesChanged;
                if (changed &&
                    !_loading &&
                    _chapter != null &&
                    _lastWidth != 0) {
                  final anchor = _visibleParagraph();
                  _restoring = true;
                  _scheduleRestore(anchor);
                }
                _lastWidth = constraints.maxWidth;
                _lastFont = settings.fontSize;
                _lastHeight = settings.lineHeight;
                if (_loading || bindingChanged) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            DesignIcons.cloudOff,
                            size: 36,
                            color: muted,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '这一章，暂时没有加载出来',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            style: TextStyle(color: muted, height: 1.6),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '阅读进度已为你保留。',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                          const SizedBox(height: 22),
                          FilledButton(
                            key: const Key('reader-error-retry'),
                            onPressed: () =>
                                _load(_chapterIndex, _requestedParagraphIndex),
                            child: const Text('重新加载'),
                          ),
                          if (book.isRemote)
                            TextButton(
                              key: const Key('reader-error-change-source'),
                              onPressed: _changeSource,
                              child: const Text('换个来源试试'),
                            ),
                        ],
                      ),
                    ),
                  );
                }
                final chapter = _forDisplay(_chapter!);
                // 工具栏用叠层浮在正文之上：高度变化不会改分页可用高度。
                return Stack(
                  children: [
                    Column(
                      children: [
                        if (_saveError != null)
                          Container(
                            width: double.infinity,
                            color: palette.errorBackground,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _saveError!,
                                    style: TextStyle(
                                      color: palette.errorInk,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  key: const Key('reader-save-retry'),
                                  onPressed: _retrySave,
                                  child: const Text('重试保存'),
                                ),
                                TextButton(
                                  key: const Key('reader-discard-progress'),
                                  onPressed: _discardAndLeave,
                                  child: const Text('不保存退出'),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: settings.flow == ReaderFlow.scrolling
                              ? _buildScrollingChapter(
                                  width: constraints.maxWidth,
                                  chapter: chapter,
                                  settings: settings,
                                  ink: ink,
                                  muted: muted,
                                )
                              : _buildPagedChapter(
                                  chapter: chapter,
                                  settings: settings,
                                  ink: ink,
                                  muted: muted,
                                ),
                        ),
                      ],
                    ),
                    if (_chromeVisible)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _readerToolTop(
                          background: background,
                          ink: ink,
                          bindingChanged: bindingChanged,
                        ),
                      )
                    else
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _readerImmersiveHead(
                          book: book,
                          muted: muted,
                        ),
                      ),
                    if (!_chromeVisible)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(29, 0, 29, 29),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: KeyedSubtree(
                                key: const Key('reader-footer-progress'),
                                child: Text(
                                  _immersiveFooterLabel(settings),
                                  key: const Key('reader-reading-progress'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_chromeVisible)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _readerToolChrome(
                          book: book,
                          settings: settings,
                          background: background,
                          ink: ink,
                          muted: muted,
                          nextDisabled: nextDisabled,
                        ),
                      ),
                    if (_selectedText != null)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: _chromeVisible ? 148 : 56,
                        child: _selectionActionBar(
                          ink: ink,
                          muted: muted,
                          background: background,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );

  /// 设计稿 `.reader-tool-top`：仅返回、书签与更多，不占用书名位。
  Widget _readerToolTop({
    required Color background,
    required Color ink,
    required bool bindingChanged,
  }) {
    final border = ink.withValues(alpha: .12);
    return Material(
      color: background.withValues(alpha: .97),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
            child: Row(
              children: [
                CircleIconButton(
                  key: const Key('reader-back'),
                  icon: DesignIcons.readerBack,
                  tooltip: '返回书架',
                  onPressed: _leave,
                ),
                const Spacer(),
                CircleIconButton(
                  key: const Key('reader-bookmark'),
                  icon: DesignIcons.readerBookmark,
                  tooltip: '添加书签笔记',
                  onPressed: _chapter == null || bindingChanged ? null : _addNote,
                ),
                const SizedBox(width: 4),
                CircleIconButton(
                  key: const Key('reader-more'),
                  icon: DesignIcons.readerMore,
                  tooltip: '阅读更多操作',
                  onPressed: _showReaderMoreSheet,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 设计稿 `.reader-head`：章名在左，章序在右（10px，不重复底栏信息）。
  Widget _readerImmersiveHead({required Book book, required Color muted}) =>
      Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 29),
              child: Row(
                children: [
                  Offstage(
                    child: KeyedSubtree(
                      key: const Key('reader-head-title'),
                      child: Text(book.title),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _chapter?.title ?? book.title,
                      key: const Key('reader-compact-heading'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: muted,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  KeyedSubtree(
                    key: const Key('reader-head-chapter'),
                    child: Text(
                      '${_chapterIndex + 1} / ${book.chapters.length}',
                      style: TextStyle(
                        fontSize: 10,
                        color: muted,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// 设计稿底栏：进度滑条 + 上一/下一 + 四等宽带文案工具。
  Widget _readerToolChrome({
    required Book book,
    required ReaderSettings settings,
    required Color background,
    required Color ink,
    required Color muted,
    required bool nextDisabled,
  }) {
    final chapterTotal = math.max(1, book.chapters.length);
    final pageTotal = math.max(1, _pageLayout?.pages.length ?? 1);
    final usePages = settings.flow == ReaderFlow.paged && !_pagedFallback;
    final progressMax = usePages
        ? pageTotal.toDouble()
        : chapterTotal.toDouble();
    final progressValue = usePages
        ? (_visiblePage + 1).clamp(1, pageTotal).toDouble()
        : (_chapterIndex + 1).clamp(1, chapterTotal).toDouble();
    // Design draft `.reader-tools`: 4 equal columns, icon above 10px label.
    Widget tool({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
    }) => Expanded(
      child: InkWell(
        key: key,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 21,
                color: onPressed == null ? muted.withValues(alpha: .45) : ink,
              ),
              const SizedBox(height: 9),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: onPressed == null ? muted.withValues(alpha: .45) : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final toolBorder = ink.withValues(alpha: .14);
    return Material(
      color: background.withValues(alpha: .97),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: toolBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: _loading || _chapterIndex == 0
                            ? null
                            : () => _jump(_chapterIndex - 1),
                        child: Text(
                          '上一章',
                          style: TextStyle(
                            fontSize: 11,
                            color: _loading || _chapterIndex == 0
                                ? muted.withValues(alpha: .5)
                                : ink,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Slider(
                        key: const Key('reader-progress-slider'),
                        min: 1,
                        max: progressMax,
                        divisions: progressMax > 1
                            ? progressMax.round() - 1
                            : null,
                        value: progressValue,
                        onChanged: _loading
                            ? null
                            : (value) {
                                final next = value.round() - 1;
                                if (usePages) {
                                  unawaited(_goToPage(next));
                                } else if (next != _chapterIndex) {
                                  unawaited(_jump(next));
                                }
                              },
                      ),
                    ),
                    TextButton(
                      key: const Key('reader-next'),
                      onPressed: nextDisabled
                          ? null
                          : () async {
                              if (_chapterIndex + 1 < book.chapters.length) {
                                await _jump(_chapterIndex + 1);
                              } else {
                                await _markFinished();
                              }
                            },
                      child: Text(
                        _chapterIndex + 1 < book.chapters.length
                            ? '下一章'
                            : (book.finished ? '已读完' : '标记读完'),
                        style: TextStyle(fontSize: 11, color: ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    tool(
                      key: const Key('reader-tool-toc'),
                      icon: DesignIcons.toolToc,
                      label: '目录',
                      onPressed: _showToc,
                    ),
                    KeyedSubtree(
                      key: const Key('reader-change-source'),
                      child: tool(
                        key: const Key('reader-tool-source'),
                        icon: DesignIcons.toolSource,
                        label: '换源',
                        onPressed: _loading || !book.isRemote
                            ? null
                            : _changeSource,
                      ),
                    ),
                    tool(
                      key: const Key('reader-tool-notes'),
                      icon: DesignIcons.toolNotes,
                      label: '笔记',
                      onPressed: () => _openNotes(book),
                    ),
                    KeyedSubtree(
                      key: const Key('reader-settings'),
                      child: tool(
                        key: const Key('reader-tool-settings'),
                        icon: DesignIcons.toolSettings,
                        label: '设置',
                        onPressed: _showSettings,
                      ),
                    ),
                  ],
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionActionBar({
    required Color ink,
    required Color muted,
    required Color background,
  }) {
    Future<void> copy() async {
      final text = _selectedText?.text;
      if (text == null) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) showMessage(context, '已复制选中文字');
    }

    const menuInk = Colors.white;
    const menuMuted = Color(0xBFFFFFFF);
    TextStyle actionStyle(bool enabled) => TextStyle(
      fontSize: 13,
      color: enabled ? menuInk : menuMuted,
    );
    Widget action({
      required Key key,
      required String label,
      required VoidCallback? onPressed,
    }) => Expanded(
      child: TextButton(
        key: key,
        style: TextButton.styleFrom(
          foregroundColor: menuInk,
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onPressed: onPressed,
        child: Text(label, style: actionStyle(onPressed != null)),
      ),
    );
    Widget divider() => Container(
      width: 1,
      height: 22,
      color: Colors.white.withValues(alpha: .18),
    );
    return Material(
      key: const Key('reader-selection-bar'),
      color: const Color(0xFF363A40),
      elevation: 8,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            action(
              key: const Key('reader-selected-mark'),
              label: '划线',
              onPressed:
                  _canMarkSelectedText ? _showSelectedTextMarkSheet : null,
            ),
            divider(),
            action(
              key: const Key('reader-selected-note'),
              label: '笔记',
              onPressed:
                  _canMarkSelectedText ? _showSelectedTextMarkSheet : null,
            ),
            divider(),
            action(
              key: const Key('reader-selection-explain'),
              label: '解释',
              onPressed: _canExplainSelection ? _openSelectionAssistant : null,
            ),
            divider(),
            action(
              key: const Key('reader-selected-copy'),
              label: '复制',
              onPressed: copy,
            ),
          ],
        ),
      ),
    );
  }

  void _openNotes(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NotesScreen(
          controller: controller,
          bookId: book.id,
          onOpen: (note) {
            Navigator.pop(context);
            _jump(note.chapterIndex, note.paragraphIndex);
          },
        ),
      ),
    );
  }

  Future<void> _showSearch() async {
    final start = controller.book(widget.bookId);
    if (start == null || !_matchesBinding(start)) return;
    final displayRulesActive = controller
        .textRules(widget.bookId)
        .any((rule) => rule.enabled);
    final hit = await showModalBottomSheet<BookTextHit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _readerSheetColor,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => Theme(
        data: _readerSheetTheme(),
        child: ReaderSearchSheet(
          book: start,
          displayRulesActive: displayRulesActive,
        ),
      ),
    );
    if (!mounted || hit == null) return;
    final latest = controller.book(widget.bookId);
    if (latest == null ||
        latest.sourceId != start.sourceId ||
        hit.chapterIndex < 0 ||
        hit.chapterIndex >= latest.chapters.length ||
        latest.chapters[hit.chapterIndex].id != hit.chapterId ||
        !latest.chapters[hit.chapterIndex].isCached) {
      showMessage(context, '书籍来源或缓存已变化，请重新查找。');
      return;
    }
    await _jump(hit.chapterIndex, hit.paragraphIndex);
  }

  /// 阅读中直接换源：换完由 [_scheduleBindingReload] 按当前位置自动重载。
  Future<void> _changeSource() async {
    final switched = await showModalBottomSheet<Book>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _readerSheetColor,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => Theme(
      data: _readerSheetTheme(),
      child: SourceSwitchSheet(controller: controller, book: book),
    ),
    );
    if (switched != null && mounted) {
      showMessage(context, '已切换到 ${switched.sourceLabel}。');
    }
  }

  void _showToc() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _readerSheetColor,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => Theme(
      data: _readerSheetTheme(),
      child: ReaderTocSheet(
      book: book,
      currentChapterIndex: _chapterIndex,
      descending: controller.settings.tocDescending,
      onOrderChanged: (descending) => controller.updateSettings(
        controller.settings.copyWith(tocDescending: descending),
      ),
      onChapterSelected: (index) {
        Navigator.pop(context);
        unawaited(_jump(index));
      },
    ),
    ),
  );

  Future<void> _updateReaderSettings(ReaderSettings settings) async {
    final generation = _generation;
    final previous = controller.settings;
    final flowChanged = previous.flow != settings.flow;
    final selectedText = flowChanged ? _selectedText : null;
    final anchor = _visibleParagraph();
    final relayout =
        flowChanged ||
        previous.fontSize != settings.fontSize ||
        previous.lineHeight != settings.lineHeight ||
        previous.paragraphSpacing != settings.paragraphSpacing ||
        previous.boldText != settings.boldText;
    if (selectedText != null && mounted) {
      setState(() => _selectedText = null);
    }
    try {
      await controller.updateSettings(settings);
    } catch (_) {
      if (selectedText != null && mounted) {
        setState(() => _selectedText = selectedText);
      }
      rethrow;
    }
    if (settings.flow != ReaderFlow.paged) _stopAutoRead();
    if (!_canUseLoad(generation) || !relayout) return;
    setState(() {
      _paragraphIndex = anchor;
      _pageLayoutKey = null;
      _restoring = true;
    });
    _scheduleRestore(anchor);
  }

  void _showSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: _readerSheetColor,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (sheetContext) => AnimatedBuilder(
      animation: controller,
      builder: (_, _) => Theme(
        data: _readerSheetTheme(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '阅读设置',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    CircleIconButton(
                      key: const Key('reader-settings-close'),
                      icon: DesignIcons.close,
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
              ReaderPreferences(
                showHeading: false,
                settings: controller.settings,
                onChanged: _updateReaderSettings,
                stylePresets: controller.readerStylePresets,
                onSaveStylePreset: (name, settings) async {
                  await controller.saveReaderStylePreset(name, settings);
                },
                onDeleteStylePreset: controller.deleteReaderStylePreset,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _openSelectionAssistant() {
    final selected = _selectedText;
    if (selected == null) {
      showMessage(context, '先选中一段文字，再来回顾它。');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _readerSheetColor,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (_) => Theme(
        data: _readerSheetTheme(),
        child: ReadingAssistantSheet(
          book: book,
          chapterTitle: _chapter?.title ?? book.title,
          paragraph: selected.text,
          readChapters: _chapterIndex,
          notes: controller.bookmarks
              .where((note) => note.bookId == widget.bookId)
              .toList(),
        ),
      ),
    );
  }

  void _addNote() {
    _paragraphIndex = _visibleParagraph();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _readerSheetColor,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => Theme(
        data: _readerSheetTheme(),
        child: NoteComposer(
          controller: controller,
          book: book,
          chapterIndex: _chapterIndex,
          paragraphIndex: _paragraphIndex,
        ),
      ),
    );
  }
}
