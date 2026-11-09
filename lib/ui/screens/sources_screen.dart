import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/app_controller.dart';
import '../../domain/book_source.dart';
import '../../domain/source_health.dart';
import '../components/common.dart';
import '../components/design.dart';
import '../components/source_edit_sheet.dart';
import '../components/source_health_sheet.dart';
import '../components/source_import_sheet.dart';
import '../design_icons.dart';
import '../theme.dart';

/// 书源管理：一个可搜索、可筛选、可批量操作的书源清单。
///
/// 与阅读（legado）一致，一个书源就是一条 JSON 声明；这里负责它们的启用状态、
/// 分组、发现开关与排序，不负责执行规则本身。
class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  final _search = TextEditingController();
  final _pending = <String>{};
  final _selected = <String>{};
  String? _group;
  bool _selecting = false;
  bool _searching = false;
  bool _validating = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant SourcesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _search.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // 书源被删掉后，选中集合里不能留下幽灵 id。
    final ids = {for (final source in widget.controller.sources) source.id};
    setState(() {
      _selected.removeWhere((id) => !ids.contains(id));
      if (_selected.isEmpty) _selecting = false;
      final groups = widget.controller.sourceGroups;
      if (_group != null && !groups.contains(_group)) _group = null;
    });
  }

  List<BookSource> get _visible {
    final query = _search.text.trim().toLowerCase();
    final group = _group;
    final matched = <(int, BookSource)>[];
    final sources = widget.controller.sources;
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      if (group != null && !source.groups.contains(group)) continue;
      if (query.isNotEmpty &&
          !source.name.toLowerCase().contains(query) &&
          !source.id.toLowerCase().contains(query) &&
          !source.groups.any((name) => name.toLowerCase().contains(query))) {
        continue;
      }
      matched.add((index, source));
    }
    // legado 的手动排序：customOrder 越小越靠前。存储层没有 customOrder 的书源会
    // 落在排序结果之外，这里按 customOrder 稳定排序一次，同值时保持控制器次序。
    matched.sort((a, b) {
      final byOrder = a.$2.customOrder.compareTo(b.$2.customOrder);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
    return [for (final entry in matched) entry.$2];
  }

  bool get _filtering => _search.text.trim().isNotEmpty || _group != null;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppTopBar(
      onBack: () => Navigator.of(context).maybePop(),
      title: '书源管理',
      actions: [
        CircleIconButton(
          key: const Key('import-source'),
          tooltip: '添加书源',
          icon: DesignIcons.plus,
          onPressed: _import,
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final horizontal = compact ? 20.0 : 40.0;
        final sources = widget.controller.sources;
        final visible = _visible;
        return ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 6, horizontal, 32),
          children: [
            _buildSummary(sources),
            const SizedBox(height: 10),
            _buildToolbar(sources: sources),
            if (_selecting) ...[
              const SizedBox(height: 12),
              _buildSelectionBar(),
            ],
            SectionLabel(
              '导入的书源',
              trailing: Text(
                _filtering
                    ? '${visible.length} / ${sources.length} 个'
                    : '${sources.length} 个',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            if (sources.isEmpty)
              EmptyState(
                title: '阅读，也可以有自己的来源',
                description:
                    '导入 Legado 风格的声明式书源。Android 仅在受限沙箱中执行规则脚本，Web 不执行脚本。',
                action: OutlinedButton.icon(
                  onPressed: _import,
                  icon: const Icon(DesignIcons.fileJson, size: 19),
                  label: const Text('导入 JSON 书源'),
                ),
              )
            else if (visible.isEmpty)
              _buildEmptyFilter()
            else
              for (final source in visible) _buildRow(source),
            const SizedBox(height: 22),
            _buildNoticeBar(),
            const SizedBox(height: 16),
            _buildAddButton(),
            SectionLabel('需要帮助'),
            RowCard(
              children: [
                ListRow(
                  key: const Key('sources-help-what'),
                  icon: DesignIcons.circleHelp,
                  title: '什么是书源？',
                  iconColor: const Color(0xFF747E8B),
                  onTap: _showHelp,
                ),
                ListRow(
                  key: const Key('sources-help-import'),
                  icon: DesignIcons.fileJson,
                  title: '从 JSON 文件导入',
                  iconColor: const Color(0xFF747E8B),
                  onTap: _import,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildCatalogNote(),
            const SizedBox(height: 10),
            const Text(
              '校验会向书源地址发起真实请求；失败只影响该来源，不会动到已有书架。',
              style: TextStyle(
                fontSize: 10,
                height: 1.8,
                color: Color(0xFFA7ADB7),
              ),
            ),
          ],
        );
      },
    ),
  );

  // ---------------------------------------------------------------- 摘要卡

  Widget _buildSummary(List<BookSource> sources) {
    final enabled = sources.where((source) => source.enabled).length;
    return Container(
      key: const Key('sources-summary'),
      padding: const EdgeInsets.fromLTRB(19, 16, 12, 17),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFF),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFE5EBF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$enabled',
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1.1,
                        color: Color(0xFF476F9D),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      '个书源已启用',
                      style: TextStyle(fontSize: 11, color: Color(0xFF9EAABA)),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('sources-validate'),
                onPressed: _validating ? null : _validateAll,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  disabledForegroundColor: AppColors.muted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: Text(_validating ? '校验中…' : '校验'),
              ),
            ],
          ),
          const SizedBox(height: 9),
          const Text(
            '只保留常用来源，找书也可以很简单。',
            style: TextStyle(
              fontSize: 11,
              height: 1.7,
              color: Color(0xFF97A5B7),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 工具栏

  Widget _buildToolbar({required List<BookSource> sources}) {
    final groups = widget.controller.sourceGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 与 legado 一致：搜索框默认收起，点工具栏的搜索按钮再展开。
        if (_searching) ...[
          SearchPill(
            hintText: '搜索书名、地址或分组',
            controller: _search,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            fieldKey: const Key('source-search'),
            trailing: IconButton(
              key: const Key('source-search-clear'),
              tooltip: '清除搜索',
              onPressed: () => setState(_search.clear),
              icon: const Icon(DesignIcons.close, size: 16, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (groups.isNotEmpty) ...[
          // 与 legado 一致：分组筛选是工具栏上的一个按钮，不是把每个分组摊在
          // 页面上。真实书源集合动辄七八十个分组，平铺会占掉十行屏幕，把书源
          // 列表挤到折叠线以下 —— 筛选器比被筛选的内容还占地方。
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              key: const Key('source-group-filter'),
              avatar: const Icon(DesignIcons.sliders, size: 18),
              label: Text(_group == null ? '全部分组' : _group!),
              onPressed: () => _openGroupFilter(groups),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                key: const Key('source-search-toggle'),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _search.clear();
                }),
                icon: Icon(_searching ? DesignIcons.close : DesignIcons.search, size: 18),
                label: const Text('搜索'),
              ),
              TextButton.icon(
                key: const Key('source-select-mode'),
                onPressed: sources.isEmpty
                    ? null
                    : () => setState(() {
                        _selecting = !_selecting;
                        if (!_selecting) _selected.clear();
                      }),
                icon: Icon(
                  _selecting ? DesignIcons.close : DesignIcons.listChecks,
                  size: 18,
                ),
                label: Text(_selecting ? '退出多选' : '选择'),
              ),
              TextButton.icon(
                key: const Key('source-export'),
                onPressed: sources.isEmpty ? null : _export,
                icon: const Icon(DesignIcons.copy, size: 18),
                label: const Text('导出'),
              ),
              TextButton.icon(
                onPressed: _import,
                icon: const Icon(DesignIcons.fileJson, size: 18),
                label: const Text('导入'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 多选条

  Widget _buildSelectionBar() => QuietPanel(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已选 ${_selected.length} 个书源',
          key: const Key('source-selection-count'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              key: const Key('source-select-all'),
              onPressed: () => setState(
                () => _selected.addAll(_visible.map((source) => source.id)),
              ),
              child: const Text('全选'),
            ),
            TextButton(
              key: const Key('source-select-invert'),
              onPressed: () => setState(() {
                // 先把结果算完再改 _selected：where 是惰性的，边迭代边改会算错。
                final visible = _visible.map((source) => source.id).toList();
                final outside = [
                  for (final id in _selected)
                    if (!visible.contains(id)) id,
                ];
                final inside = [
                  for (final id in visible)
                    if (!_selected.contains(id)) id,
                ];
                _selected
                  ..clear()
                  ..addAll(outside)
                  ..addAll(inside);
              }),
              child: const Text('反选'),
            ),
            TextButton(
              key: const Key('source-batch-enable'),
              onPressed: _selected.isEmpty ? null : () => _setEnabled(true),
              child: const Text('启用'),
            ),
            TextButton(
              key: const Key('source-batch-disable'),
              onPressed: _selected.isEmpty ? null : () => _setEnabled(false),
              child: const Text('停用'),
            ),
            TextButton(
              key: const Key('source-batch-delete'),
              onPressed: _selected.isEmpty ? null : _deleteSelected,
              child: const Text(
                '删除',
                style: TextStyle(color: Color(0xFFB54444)),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildEmptyFilter() => QuietPanel(
    child: Column(
      children: [
        const Text('没有匹配的书源', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
          '换个关键词，或者把分组切回「全部」。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('source-clear-filter'),
          onPressed: _clearFilter,
          child: const Text('清除筛选'),
        ),
      ],
    ),
  );

  // ------------------------------------------------------------ 底部区块

  Widget _buildNoticeBar() => Container(
    key: const Key('sources-notice'),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    decoration: BoxDecoration(
      color: const Color(0xFFFBF7EF),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(DesignIcons.info, size: 15, color: Color(0xFFAC9874)),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '书源决定可以搜索到的内容。失效时，先校验或换个来源即可。',
            style: TextStyle(
              fontSize: 10,
              height: 1.8,
              color: Color(0xFFAC9874),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildAddButton() => SizedBox(
    width: double.infinity,
    child: TextButton.icon(
      key: const Key('sources-add'),
      onPressed: _import,
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFFF2F5FA),
        foregroundColor: const Color(0xFF54749D),
        minimumSize: const Size.fromHeight(46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 14),
      ),
      icon: const Icon(DesignIcons.plus, size: 18),
      label: const Text('添加书源'),
    ),
  );

  Widget _buildCatalogNote() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(
          DesignIcons.bookOpen,
          size: 14,
          color: Color(0xFFA7ADB7),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          '阅读 · 公版书库：${widget.controller.catalog.length} 部经典节选，内置离线可用。',
          style: const TextStyle(
            fontSize: 10,
            height: 1.8,
            color: Color(0xFFA7ADB7),
          ),
        ),
      ),
    ],
  );

  // ------------------------------------------------------------------ 行

  Widget _buildRow(BookSource source) {
    final selected = _selected.contains(source.id);
    // 行内次级信息与名称左对齐：选择图标 + 图标块 + 间距。
    final indent = (_selecting ? 28.0 : 0.0) + 51;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => setState(() {
        _selecting = true;
        _selected.add(source.id);
      }),
      onTap: _selecting
          ? () => setState(() {
              if (!_selected.remove(source.id)) _selected.add(source.id);
              if (_selected.isEmpty) _selecting = false;
            })
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 19),
        decoration: BoxDecoration(
          color: selected ? AppColors.softBlue : null,
          border: const Border(bottom: BorderSide(color: Color(0xFFEDF0F5))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_selecting)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      selected
                          ? DesignIcons.circleCheck
                          : DesignIcons.circle,
                      size: 20,
                      color: selected ? AppColors.blue : AppColors.muted,
                    ),
                  ),
                Container(
                  width: 39,
                  height: 39,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F5FA),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    DesignIcons.globe,
                    size: 19,
                    color: Color(0xFF8CA1BD),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        key: Key('source-name-${source.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: _statusDotColor(source),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _statusLine(source),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                height: 1.5,
                                color: Color(0xFFA7B0BE),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                KeyedSubtree(
                  key: Key('source-switch-${source.id}'),
                  child: SwitchDot(
                    value: source.enabled,
                    semanticLabel: '${source.name}启用状态',
                    onChanged: _pending.contains(source.id)
                        ? null
                        : (enabled) => _toggle(source, enabled),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(left: indent, top: 8, right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFA7B0BE),
                    ),
                  ),
                  if (source.groups.any(
                    (group) => !SourceHealthTag.isInvalid(group),
                  )) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        // Health verdicts live in the group field too, but they
                        // are reported by the status line above; showing them as
                        // neutral chips would read like user-chosen groups.
                        for (final group in source.groups)
                          if (!SourceHealthTag.isInvalid(group))
                            _GroupTag(label: group),
                      ],
                    ),
                  ],
                  if (source.comment.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      source.comment,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.6,
                        color: Color(0xFFA7B0BE),
                      ),
                    ),
                  ],
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 2,
                    children: [
                      TextButton(
                        key: Key('source-edit-${source.id}'),
                        onPressed: () => _edit(source),
                        child: const Text('编辑'),
                      ),
                      TextButton(
                        onPressed: () => _health(source),
                        child: const Text('检查书源'),
                      ),
                      PopupMenuButton<String>(
                        key: Key('source-menu-${source.id}'),
                        tooltip: '${source.name}的更多操作',
                        icon: const Icon(
                          DesignIcons.ellipsis,
                          size: 20,
                          color: AppColors.muted,
                        ),
                        onSelected: (value) => _onMenu(source, value),
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'top', child: Text('置顶')),
                          if (source.hasExplore)
                            PopupMenuItem(
                              value: 'explore',
                              child: Text(
                                source.enabledExplore ? '关闭发现' : '开启发现',
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'view',
                            child: Text('查看规则'),
                          ),
                          const PopupMenuItem(
                            value: 'copy',
                            child: Text('复制 JSON'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              '删除',
                              style: TextStyle(color: Color(0xFFB54444)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 状态点沿用设计稿的三种语义色：正常 / 需注意 / 已停用。
  Color _statusDotColor(BookSource source) {
    if (source.invalidGroups.isNotEmpty) return const Color(0xFFC7AA70);
    if (!source.enabled) return const Color(0xFFA6AFBD);
    return const Color(0xFF74AA92);
  }

  // ---------------------------------------------------------- 校验与说明

  Future<void> _validateAll() async {
    final targets = [
      for (final source in _visible)
        if (source.enabled) source,
    ];
    if (targets.isEmpty) {
      showMessage(context, '没有可校验的书源。');
      return;
    }
    setState(() => _validating = true);
    var failed = 0;
    for (final source in targets) {
      if (!mounted) return;
      try {
        final report = await widget.controller.checkSourceHealth(source.id);
        if (report.hasFailures) failed++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _validating = false);
    final usable = targets.length - failed;
    showMessage(
      context,
      failed == 0 ? '校验完成，$usable 个书源都可用。' : '校验完成：$usable 个可用，$failed 个需要处理。',
    );
  }

  void _showHelp() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('什么是书源？'),
      content: const Text(
        '书源是一份 JSON 声明：它告诉应用去哪个站点搜索，目录与正文怎么解析。'
        '导入后会加入搜索与换源；停用只是不再参与，删除也不会影响已经缓存的书。',
        style: TextStyle(fontSize: 13, height: 1.8),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  String _statusLine(BookSource source) {
    final buffer = StringBuffer(source.enabled ? '已启用' : '已停用');
    if (!source.enabled) {
      buffer.write(' · 不参与搜索与换源');
    } else if (!source.hasExplore) {
      buffer.write(' · 无发现规则');
    } else {
      buffer.write(source.enabledExplore ? ' · 参与发现' : ' · 不参与发现');
    }
    if (source.customOrder != 0) buffer.write(' · 手动排序');
    // respondTime is written by every health check, so it doubles as "how long
    // this source last took" — the same thing Legado shows and sorts by.
    if (source.respondTime > 0) {
      buffer.write(' · 响应 ${(source.respondTime / 1000).toStringAsFixed(1)} 秒');
    }
    final invalid = source.invalidGroups;
    if (invalid.isNotEmpty) buffer.write(' · ${invalid.join('、')}');
    return buffer.toString();
  }

  // --------------------------------------------------------------- 行为

  void _clearFilter() => setState(() {
    _search.clear();
    _group = null;
  });

  /// 分组筛选放在面板里，和 legado 的 `showGroupFilterSheet` 一致。
  ///
  /// 每组带上它包含的源数，用户才知道「点下去会剩几条」；计数与工具栏用的是
  /// 同一份 `widget.controller.sources`，不会和列表打架。
  Future<void> _openGroupFilter(List<String> groups) async {
    final sources = widget.controller.sources;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '按分组筛选',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: ListView(
                  key: const Key('source-group-list'),
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      key: const Key('source-group-all'),
                      title: const Text('全部'),
                      trailing: Text(
                        '${sources.length}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      selected: _group == null,
                      onTap: () => Navigator.pop(context, ''),
                    ),
                    for (final group in groups)
                      ListTile(
                        key: Key('source-group-$group'),
                        title: Text(group),
                        trailing: Text(
                          '${sources.where((source) => source.groups.contains(group)).length}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        selected: _group == group,
                        onTap: () => Navigator.pop(context, group),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _group = picked.isEmpty ? null : picked);
  }

  Future<void> _toggle(BookSource source, bool enabled) async {
    setState(() => _pending.add(source.id));
    try {
      await widget.controller.setSourceEnabled(source, enabled);
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    } finally {
      if (mounted) setState(() => _pending.remove(source.id));
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    final targets = [
      for (final source in widget.controller.sources)
        if (_selected.contains(source.id)) source,
    ];
    for (final source in targets) {
      try {
        await widget.controller.setSourceEnabled(source, enabled);
      } catch (error) {
        if (mounted) showMessage(context, errorMessage(error));
        break;
      }
    }
    if (mounted) {
      showMessage(context, enabled ? '已启用选中的书源。' : '已停用选中的书源。');
    }
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    if (!await confirmRemoval(
      context,
      '移除选中的 ${ids.length} 个书源？',
      '已缓存的书籍仍可阅读，新的章节需要重新导入书源才能获取。',
    )) {
      return;
    }
    try {
      await widget.controller.deleteSources(ids);
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selecting = false;
      });
      showMessage(context, '已移除 ${ids.length} 个书源。');
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    }
  }

  Future<void> _export() async {
    final selected = _selected.isEmpty ? null : _selected;
    final String text;
    final int count;
    if (selected == null) {
      text = widget.controller.exportSourcesJson();
      count = widget.controller.sources.length;
    } else {
      final sources = [
        for (final source in widget.controller.sources)
          if (selected.contains(source.id)) source,
      ];
      text = const JsonEncoder.withIndent(
        '  ',
      ).convert([for (final source in sources) source.toJson()]);
      count = sources.length;
    }
    if (count == 0) {
      showMessage(context, '没有可导出的书源。');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
      return;
    }
    if (mounted) {
      showMessage(context, '已复制 $count 个书源的 JSON，可粘贴到其他阅读客户端。');
    }
  }

  void _onMenu(BookSource source, String value) {
    switch (value) {
      case 'top':
        _moveToTop(source);
      case 'explore':
        _toggleExplore(source);
      case 'view':
        _view(source);
      case 'copy':
        _copy(source);
      case 'delete':
        _delete(source);
    }
  }

  Future<void> _moveToTop(BookSource source) async {
    try {
      await widget.controller.moveSourceToTop(source.id);
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    }
  }

  Future<void> _toggleExplore(BookSource source) async {
    try {
      await widget.controller.setSourceEnabledExplore(
        source,
        !source.enabledExplore,
      );
      if (!mounted) return;
      showMessage(
        context,
        source.enabledExplore
            ? '“${source.name}”已关闭发现。'
            : '“${source.name}”已开启发现。',
      );
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    }
  }

  Future<void> _copy(BookSource source) async {
    final json = const JsonEncoder.withIndent('  ').convert(source.toJson());
    try {
      await Clipboard.setData(ClipboardData(text: json));
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
      return;
    }
    if (mounted) showMessage(context, '书源 JSON 已复制。');
  }

  Future<void> _delete(BookSource source) async {
    if (!await confirmRemoval(
      context,
      '移除“${source.name}”？',
      '已缓存的书籍仍可阅读，新的章节需要重新导入书源才能获取。',
    )) {
      return;
    }
    try {
      await widget.controller.deleteSources([source.id]);
    } catch (error) {
      if (mounted) showMessage(context, errorMessage(error));
    }
  }

  Future<void> _edit(BookSource source) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (_) =>
          SourceEditSheet(controller: widget.controller, source: source),
    );
    if (saved == true && mounted) showMessage(context, '书源已保存。');
  }

  void _import() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 680),
    builder: (_) => SourceImportSheet(controller: widget.controller),
  );

  void _health(BookSource source) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) =>
        SourceHealthSheet(controller: widget.controller, source: source),
  );

  void _view(BookSource source) {
    final json = const JsonEncoder.withIndent('  ').convert(source.toJson());
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(source.name),
        content: SizedBox(
          width: 560,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _copy(source),
            child: const Text('复制 JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _GroupTag extends StatelessWidget {
  const _GroupTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.softBlue,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, color: AppColors.blue),
    ),
  );
}
