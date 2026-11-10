import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
import '../components/note_composer.dart';
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
import 'notes_screen.dart';

/// Vertical rhythm shared by the paged and scrolling readers. The paginator
/// measures against these, so a page never renders text it did not reserve room for.
const double _pagedTopPadding = 4;

/// 页脚叠在正文之上，正文底部要为它留出高度，最后一行才不会被压住。
const double _pagedBottomPadding = 44;

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

/// 工具顶栏「更多」菜单里的动作；设计稿的 reader-more sheet 在这里收敛成一个
/// PopupMenu：搜索、笔记与主题切换不再占据顶栏的一排图标位。
enum _ReaderMoreAction { search, notes, theme }

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
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => Theme(
        data: appTheme(),
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
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => Theme(
        data: appTheme(),
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
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheetContext) => Theme(
        data: appTheme(),
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
      if (mounted) showMessage(context, '又读完一本，下一本见。');
    }
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
    child: SingleChildScrollView(
      key: const Key('reader-scrolling-view'),
      controller: _scroll,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              width < 650 ? 24 : 48,
              36,
              width < 650 ? 24 : 48,
              104,
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
                    leading: const Icon(Icons.pause_circle_outline),
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
                      leading: const Icon(Icons.auto_mode_outlined),
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

  void _showReadAloudControls() {
    final raw = _chapter;
    final chapter = raw == null ? null : _forDisplay(raw);
    final paragraph = chapter == null || chapter.paragraphs.isEmpty
        ? 0
        : _visibleParagraph().clamp(0, chapter.paragraphs.length - 1).toInt();
    final text = chapter == null
        ? ''
        : ReadAloudText.fromParagraphs(chapter.paragraphs.skip(paragraph));
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: _readAloud,
        builder: (context, _) {
          final state = _readAloud.state;
          final detail = !_readAloud.isSupported
              ? '当前平台不支持本机朗读。'
              : switch (state) {
                  ReadAloudState.unavailable => '当前平台不支持本机朗读。',
                  ReadAloudState.error => '设备无法启动本机朗读，请确认已安装中文系统语音。',
                  ReadAloudState.speaking => '正在朗读当前章节的本地文本。',
                  ReadAloudState.idle when text.isEmpty => '当前位置没有可朗读的正文。',
                  ReadAloudState.idle =>
                    '从当前段落开始，单次最多朗读 ${ReadAloudText.maxCharacters} 个字符。应用不会上传正文；请在系统中选择已安装的本地中文语音。',
                };
          return AlertDialog(
            title: const Text('设备朗读'),
            content: Text(detail, style: const TextStyle(height: 1.7)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
              if (_readAloud.isSpeaking)
                FilledButton(
                  key: const Key('reader-read-aloud-stop'),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    unawaited(_readAloud.stop());
                  },
                  child: const Text('停止朗读'),
                )
              else if (_readAloud.isSupported && text.isNotEmpty)
                FilledButton(
                  key: const Key('reader-read-aloud-start'),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    unawaited(_readAloud.start(text));
                  },
                  child: const Text('从当前位置朗读'),
                ),
            ],
          );
        },
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

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

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
      final horizontalPadding = constraints.maxWidth < 650 ? 24.0 : 48.0;
      final contentWidth = math.max(
        1.0,
        math.min(760.0, constraints.maxWidth) - horizontalPadding * 2,
      );

      final contentHeight = math.max(
        1.0,
        constraints.maxHeight - _pagedTopPadding - _pagedBottomPadding,
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
          '${chapter.id}|$_displayRulesRevision|${contentWidth.toStringAsFixed(1)}|'
          '${contentHeight.toStringAsFixed(1)}|${settings.fontSize}|'
          '${settings.lineHeight}|${settings.paragraphSpacing}|${settings.boldText}';
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
                          _pagedTopPadding,
                          horizontalPadding,
                          _pagedBottomPadding,
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
          if (_chromeVisible)
            Positioned(
              right: 16,
              bottom: 8,
              child: Text(
                '${_visiblePage + 1}/${layout.pages.length}',
                key: const Key('reader-page-indicator'),
                style: TextStyle(fontSize: 11, color: muted),
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
      final compactControls =
          MediaQuery.sizeOf(context).width < 480 ||
          MediaQuery.textScalerOf(context).scale(12) > 18;
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
            appBar: AppBar(
              backgroundColor: background,
              foregroundColor: ink,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: false,
              automaticallyImplyLeading: false,
              titleSpacing: _chromeVisible ? 16 : 24,
              leading: _chromeVisible
                  ? IconButton(
                      key: const Key('reader-back'),
                      tooltip: '返回书架',
                      onPressed: _leave,
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    )
                  : null,
              title: _chromeVisible
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KeyedSubtree(
                          key: const Key('reader-head-title'),
                          child: Text(
                            book.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: ink,
                            ),
                          ),
                        ),
                        KeyedSubtree(
                          key: const Key('reader-head-chapter'),
                          child: Text(
                            '${book.author} · ${_chapterIndex + 1}/${book.chapters.length} 章',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      _chapter?.title ?? book.title,
                      key: const Key('reader-compact-heading'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
              actions: _chromeVisible
                  ? [
                      // 工具顶栏按设计稿只留三件事：返回（leading）、书签、更多。
                      // 搜索、笔记与更多操作收进 reader-more 菜单。
                      IconButton(
                        key: const Key('reader-bookmark'),
                        tooltip: '添加书签笔记',
                        onPressed: _chapter == null || bindingChanged
                            ? null
                            : _addNote,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 23),
                      ),
                      PopupMenuButton<_ReaderMoreAction>(
                        key: const Key('reader-more'),
                        tooltip: '阅读更多操作',
                        icon: const Icon(Icons.more_horiz, size: 23),
                        color: Colors.white,
                        itemBuilder: (menuContext) => [
                          PopupMenuItem(
                            key: const Key('reader-search'),
                            value: _ReaderMoreAction.search,
                            enabled: _chapter != null && !bindingChanged,
                            child: const Row(
                              children: [
                                Icon(Icons.search, size: 20),
                                SizedBox(width: 12),
                                Text('书内查找'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            key: const Key('reader-tool-notes'),
                            value: _ReaderMoreAction.notes,
                            child: const Row(
                              children: [
                                Icon(Icons.notes_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('本书笔记'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            key: const Key('reader-tool-theme'),
                            value: _ReaderMoreAction.theme,
                            child: Row(
                              children: [
                                Icon(
                                  dark
                                      ? Icons.light_mode_outlined
                                      : Icons.dark_mode_outlined,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(dark ? '切换到日间' : '切换到夜间'),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (action) {
                          switch (action) {
                            case _ReaderMoreAction.search:
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) unawaited(_showSearch());
                              });
                            case _ReaderMoreAction.notes:
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _openNotes(book);
                              });
                            case _ReaderMoreAction.theme:
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) unawaited(_toggleTheme());
                              });
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                    ]
                  : const [],
            ),
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
                          Text(
                            _error!,
                            style: TextStyle(color: ink),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton(
                            onPressed: () =>
                                _load(_chapterIndex, _requestedParagraphIndex),
                            child: const Text('重新加载'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final chapter = _forDisplay(_chapter!);
                return Column(
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
                );
              },
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Container(
                color: background,
                // 高度必须与工具栏显隐无关：底栏一变高就会改动正文可用高度，
                // 触发重新分页并把读者从当前页弹走。
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: LayoutBuilder(
                        builder: (context, barConstraints) {
                          // 按底栏的真实可用宽度决定按钮形态，而不是只看屏宽：
                          // 文字按钮（上一章/下一章）各占 84pt，加上换源等四个
                          // 图标在 360pt 级别的宽度上会横向溢出。
                          final barCompact =
                              compactControls || barConstraints.maxWidth < 420;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: _chromeVisible
                                ? [
                                    Tooltip(
                                      message: '上一章',
                                      child: TextButton(
                                        onPressed:
                                            _loading || _chapterIndex == 0
                                            ? null
                                            : () => _jump(_chapterIndex - 1),
                                        child: barCompact
                                            ? Icon(
                                                Icons.skip_previous,
                                                size: 22,
                                                color:
                                                    _loading ||
                                                        _chapterIndex == 0
                                                    ? muted.withValues(
                                                        alpha: .5,
                                                      )
                                                    : ink,
                                              )
                                            : Text(
                                                '‹ 上一章',
                                                style: TextStyle(
                                                  color:
                                                      _loading ||
                                                          _chapterIndex == 0
                                                      ? muted.withValues(
                                                          alpha: .5,
                                                        )
                                                      : ink,
                                                  fontSize: 12,
                                                ),
                                              ),
                                      ),
                                    ),
                                    KeyedSubtree(
                                      key: const Key('reader-tool-toc'),
                                      child: IconButton(
                                        tooltip: '章节目录',
                                        visualDensity: barCompact
                                            ? VisualDensity.compact
                                            : null,
                                        padding: barCompact
                                            ? EdgeInsets.zero
                                            : null,
                                        onPressed: _showToc,
                                        icon: Icon(
                                          Icons.format_list_bulleted,
                                          color: ink,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    KeyedSubtree(
                                      key: const Key('reader-tool-source'),
                                      child: IconButton(
                                        key: const Key('reader-change-source'),
                                        tooltip: '换源',
                                        visualDensity: barCompact
                                            ? VisualDensity.compact
                                            : null,
                                        padding: barCompact
                                            ? EdgeInsets.zero
                                            : null,
                                        onPressed: _loading || !book.isRemote
                                            ? null
                                            : _changeSource,
                                        icon: Icon(
                                          Icons.swap_horiz,
                                          color: _loading || !book.isRemote
                                              ? muted.withValues(alpha: .5)
                                              : ink,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    KeyedSubtree(
                                      key: const Key('reader-tool-settings'),
                                      child: IconButton(
                                        key: const Key('reader-settings'),
                                        tooltip: '阅读设置',
                                        onPressed: _showSettings,
                                        icon: Icon(
                                          Icons.text_fields,
                                          color: ink,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                    Tooltip(
                                      message:
                                          _chapterIndex + 1 <
                                              book.chapters.length
                                          ? '下一章'
                                          : (book.finished ? '已读完' : '标记读完'),
                                      child: TextButton(
                                        key: const Key('reader-next'),
                                        onPressed: nextDisabled
                                            ? null
                                            : () async {
                                                if (_chapterIndex + 1 <
                                                    book.chapters.length) {
                                                  await _jump(
                                                    _chapterIndex + 1,
                                                  );
                                                } else {
                                                  await _markFinished();
                                                }
                                              },
                                        child: barCompact
                                            ? Icon(
                                                _chapterIndex + 1 <
                                                        book.chapters.length
                                                    ? Icons.skip_next
                                                    : Icons
                                                          .check_circle_outline,
                                                size: 22,
                                                color: nextDisabled
                                                    ? muted.withValues(
                                                        alpha: .5,
                                                      )
                                                    : ink,
                                              )
                                            : Text(
                                                _chapterIndex + 1 <
                                                        book.chapters.length
                                                    ? '下一章 ›'
                                                    : (book.finished
                                                          ? '已读完 ✓'
                                                          : '标记读完'),
                                                style: TextStyle(
                                                  color: ink,
                                                  fontSize: 12,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ]
                                : [
                                    Expanded(
                                      child: KeyedSubtree(
                                        key: const Key('reader-footer-chapter'),
                                        child: Text(
                                          _chapter?.title ?? book.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: KeyedSubtree(
                                        key: const Key(
                                          'reader-footer-progress',
                                        ),
                                        child: Text(
                                          settings.flow == ReaderFlow.paged &&
                                                  !_pagedFallback
                                              ? '第 ${_chapterIndex + 1} 章 · ${_visiblePage + 1}/${_pageLayout?.pages.length ?? 1} 页'
                                              : '第 ${_chapterIndex + 1} 章 · 滚动阅读',
                                          key: const Key(
                                            'reader-reading-progress',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

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
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => Theme(
        data: appTheme(),
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
      backgroundColor: const Color(0xFFF1EDE1),
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => SourceSwitchSheet(controller: controller, book: book),
    );
    if (switched != null && mounted) {
      showMessage(context, '已切换到 ${switched.sourceLabel}。');
    }
  }

  void _showToc() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => ReaderTocSheet(
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
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (sheetContext) => AnimatedBuilder(
      animation: controller,
      builder: (_, _) => Theme(
        data: appTheme(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动条已经隔开了标题，这里不再加分隔线：多一行辅助入口就会把
              // 下方的排版区（含背景圆点）推出短屏可视范围。
              ListTile(
                key: const Key('reader-auto-read'),
                contentPadding: EdgeInsets.zero,
                title: const Text('自动翻页'),
                subtitle: Text(
                  _autoReadActive ? '当前每 ${_autoReadSeconds!} 秒翻一页' : '仅支持分页阅读',
                ),
                trailing: Icon(
                  _autoReadActive
                      ? Icons.pause_circle_outline
                      : Icons.auto_mode_outlined,
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
                      ? Icons.stop_circle_outlined
                      : Icons.volume_up_outlined,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showReadAloudControls();
                  });
                },
              ),
              ListTile(
                key: const Key('reader-mark'),
                contentPadding: EdgeInsets.zero,
                title: const Text('段落标注'),
                subtitle: const Text('标注当前显示段落，可添加本地备注'),
                trailing: const Icon(Icons.highlight_alt_outlined),
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
                trailing: const Icon(Icons.text_fields),
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
                trailing: const Icon(Icons.auto_awesome_outlined),
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
                trailing: const Icon(Icons.collections_bookmark_outlined),
                onTap: () {
                  Navigator.pop(sheetContext);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) unawaited(_showMarkManager());
                  });
                },
              ),
              const Divider(height: 28),
              // 排版六行放在辅助功能之后：面板一打开先看到自动翻页/朗读/标注，
              // 往下滑才是字号、行距与背景。设计稿把六行放在首位，但阅读页的
              // 这些操作入口也依赖面板顶部可达，两者冲突时优先保住操作可达性。
              ReaderPreferences(
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
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (_) => Theme(
        data: appTheme(),
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
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => Theme(
        data: appTheme(),
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
