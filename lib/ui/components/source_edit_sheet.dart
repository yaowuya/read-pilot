import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../domain/book_source.dart';
import '../theme.dart';
import 'common.dart';

/// One editable rule group, mirroring legado's 搜索 / 发现 / 详情 / 目录 / 正文
/// tabs. The field names are the legado JSON keys inside the rule object.
class _RuleGroup {
  const _RuleGroup(this.key, this.title, this.hint, this.fields);

  final String key;
  final String title;
  final String hint;
  final Map<String, String> fields;
}

const _ruleGroups = <_RuleGroup>[
  _RuleGroup('ruleSearch', '搜索', '搜索结果页里每一本书的取法。', {
    'bookList': '搜索结果列表',
    'name': '书名',
    'author': '作者',
    'intro': '简介',
    'kind': '分类',
    'lastChapter': '最新章节',
    'bookUrl': '详情页链接',
    'coverUrl': '封面链接',
  }),
  _RuleGroup('ruleExplore', '发现', '发现页列表项的取法，字段与搜索一致。', {
    'bookList': '列表项',
    'name': '书名',
    'author': '作者',
    'intro': '简介',
    'kind': '分类',
    'lastChapter': '最新章节',
    'bookUrl': '详情页链接',
    'coverUrl': '封面链接',
  }),
  _RuleGroup('ruleBookInfo', '详情', '详情页里书籍信息的取法。', {
    'name': '书名',
    'author': '作者',
    'intro': '简介',
    'kind': '分类',
    'lastChapter': '最新章节',
    'coverUrl': '封面链接',
    'tocUrl': '目录页链接',
  }),
  _RuleGroup('ruleToc', '目录', '目录页里章节的取法。', {
    'chapterList': '章节列表',
    'chapterName': '章节名称',
    'chapterUrl': '章节链接',
    'nextTocUrl': '下一页目录',
  }),
  _RuleGroup('ruleContent', '正文', '正文页里章节内容的取法。', {
    'title': '章节标题',
    'content': '正文内容',
    'nextContentUrl': '下一页正文',
    'replaceRegex': '正文替换',
  }),
];

/// Every section of the editor, in the order the chips render.
const _sectionTitles = <String>['基础', '搜索', '发现', '详情', '目录', '正文', '高级'];

/// Sheet index of the raw JSON editor; the rule sections sit between 基础 and it.
int get _jsonSection => _sectionTitles.length - 1;

/// 书源编辑面板。
///
/// Legado 把一个书源当作「一串 JSON + 一组规则」，所以这里既不隐藏原始 JSON，
/// 也不假装能校验只会执行到一半的规则：表单字段逐项写回，规则按组整块重写，
/// 高级页直接编辑原始 JSON，未知字段原样保留。
class SourceEditSheet extends StatefulWidget {
  const SourceEditSheet({
    super.key,
    required this.controller,
    required this.source,
  });

  final AppController controller;
  final BookSource source;

  @override
  State<SourceEditSheet> createState() => _SourceEditSheetState();
}

class _SourceEditSheetState extends State<SourceEditSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _group = TextEditingController();
  final _comment = TextEditingController();
  final _searchUrl = TextEditingController();
  final _exploreUrl = TextEditingController();
  final _raw = TextEditingController();
  final _ruleFields = <String, Map<String, TextEditingController>>{};
  late BookSource _current;
  int _section = 0;
  bool _enabled = true;
  bool _enabledExplore = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFrom(widget.source);
  }

  @override
  void dispose() {
    for (final field in [
      _name,
      _url,
      _group,
      _comment,
      _searchUrl,
      _exploreUrl,
    ]) {
      field.dispose();
    }
    _raw.dispose();
    for (final group in _ruleFields.values) {
      for (final field in group.values) {
        field.dispose();
      }
    }
    super.dispose();
  }

  /// 用一份书源覆盖所有输入控件。切换高级页时会先解析再回到这里，所以表单
  /// 与 JSON 永远是同一份数据。
  void _loadFrom(BookSource source) {
    _current = source;
    _name.text = source.name;
    _url.text = source.id;
    _group.text = source.group;
    _comment.text = source.comment;
    _searchUrl.text = source.searchUrl;
    _exploreUrl.text = source.definition.exploreUrl ?? '';
    _enabled = source.enabled;
    _enabledExplore = source.enabledExplore;
    for (final group in _ruleGroups) {
      final values = _ruleFields.putIfAbsent(
        group.key,
        () => {
          for (final field in group.fields.keys) field: TextEditingController(),
        },
      );
      for (final entry in values.entries) {
        final raw = source.definition.rules(group.key)[entry.key];
        entry.value.text = raw is String ? raw : '';
      }
    }
    _raw.text = const JsonEncoder.withIndent('  ').convert(_mergedJson());
  }

  /// 表单当前值合并进原始 JSON。
  ///
  /// 起点始终是 [BookSource.toJson]，所以用户没改过的字段（包括本项目不认识
  /// 的 legado 扩展字段）不会被这张表单丢掉。
  Map<String, dynamic> _mergedJson() {
    final json = _current.toJson();
    void putOrRemove(String key, String value) {
      final text = value.trim();
      if (text.isEmpty) {
        json.remove(key);
      } else {
        json[key] = text;
      }
    }

    json['bookSourceName'] = _name.text.trim();
    json['bookSourceUrl'] = _url.text.trim();
    json['enabled'] = _enabled;
    json['enabledExplore'] = _enabledExplore;
    putOrRemove('bookSourceGroup', _group.text);
    putOrRemove('bookSourceComment', _comment.text);
    putOrRemove('searchUrl', _searchUrl.text);
    putOrRemove('exploreUrl', _exploreUrl.text);
    for (final group in _ruleGroups) {
      final current = json[group.key];
      final rules = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      for (final entry in (_ruleFields[group.key] ?? const {}).entries) {
        final text = entry.value.text.trim();
        if (text.isEmpty) {
          rules.remove(entry.key);
        } else {
          rules[entry.key] = text;
        }
      }
      if (rules.isEmpty) {
        json.remove(group.key);
      } else {
        json[group.key] = rules;
      }
    }
    return json;
  }

  BookSource _build() => BookSource(_mergedJson());

  /// 解析高级页里的原始 JSON。错误信息保持中文，不把 JSON 解析器的英文原文
  /// 直接丢给用户。
  BookSource _parseRaw() {
    final text = _raw.text.trim();
    if (text.isEmpty) {
      throw const FormatException('书源 JSON 不能为空。');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('书源 JSON 无法解析，请检查括号与引号。');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('书源 JSON 必须是一个对象。');
    }
    return BookSource(decoded);
  }

  void _select(int index) {
    if (index == _section) return;
    if (_section == _jsonSection) {
      // 离开高级页时先把 JSON 收回表单，解析失败就留在原地并提示。
      try {
        _loadFrom(_parseRaw());
      } catch (error) {
        setState(() => _error = errorMessage(error));
        return;
      }
      setState(() {
        _section = index;
        _error = null;
      });
      return;
    }
    setState(() {
      _section = index;
      _error = null;
    });
    if (index == _jsonSection) {
      _raw.text = const JsonEncoder.withIndent('  ').convert(_mergedJson());
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final edited = _section == _jsonSection ? _parseRaw() : _build();
      // `bookSourceUrl` 是书源的主键，改地址等于换记录，由 controller 负责把旧
      // 记录清掉。
      await widget.controller.updateSource(
        edited,
        previousId: widget.source.id,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(error);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = math.max(
      280.0,
      MediaQuery.sizeOf(context).height * .86 - insets,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + insets),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '编辑书源',
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_saving)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '保存后会立即用于“${widget.source.name}”的搜索与发现。',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _sectionTitles.length; index++)
                    ChoiceChip(
                      key: Key('source-edit-section-$index'),
                      label: Text(_sectionTitles[index]),
                      selected: _section == index,
                      onSelected: (_) => _select(index),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(child: _buildSection(context)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    key: const Key('source-edit-cancel'),
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('source-edit-save'),
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '正在保存…' : '保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context) {
    if (_section == _jsonSection) return _buildJsonSection(context);
    if (_section == 0) return _buildBaseSection(context);
    final group = _ruleGroups[_section - 1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.hint,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.muted,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 12),
        if (group.key == 'ruleSearch')
          _LabeledField(
            fieldKey: const Key('source-edit-search-url'),
            label: '搜索页地址',
            hint: '/search?q={{key}}',
            controller: _searchUrl,
            maxLines: 2,
          ),
        if (group.key == 'ruleExplore')
          _LabeledField(
            fieldKey: const Key('source-edit-explore-url'),
            label: '发现页地址',
            hint: '分类::链接，每行一个',
            controller: _exploreUrl,
            maxLines: 4,
          ),
        for (final entry in group.fields.entries)
          _LabeledField(
            fieldKey: Key('rule-${group.key}-${entry.key}'),
            label: entry.value,
            hint: '规则字段 ${entry.key}',
            controller: _ruleFields[group.key]![entry.key]!,
          ),
        const SizedBox(height: 4),
        Text(
          '规则支持 CSS、XPath 子集与 JSONPath；留空表示这个字段沿用默认取法。',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.muted,
            height: 1.7,
          ),
        ),
      ],
    );
  }

  Widget _buildBaseSection(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _LabeledField(
        fieldKey: const Key('source-edit-name'),
        label: '书源名称',
        hint: '书架与搜索结果里显示的名字',
        controller: _name,
      ),
      _LabeledField(
        fieldKey: const Key('source-edit-url'),
        label: '书源地址',
        hint: 'https://example.com',
        controller: _url,
        keyboardType: TextInputType.url,
      ),
      _LabeledField(
        fieldKey: const Key('source-edit-group'),
        label: '分组',
        hint: '多个分组用逗号或分号分隔，例如：玄幻,都市',
        controller: _group,
      ),
      _LabeledField(
        fieldKey: const Key('source-edit-comment'),
        label: '备注',
        hint: '只给自己看的一句话',
        controller: _comment,
        maxLines: 2,
      ),
      _SwitchRow(
        switchKey: const Key('source-edit-enabled'),
        title: '启用搜索',
        description: '停用后不参与搜索与换源，已缓存的章节仍可阅读。',
        value: _enabled,
        onChanged: (value) => setState(() => _enabled = value),
      ),
      const SizedBox(height: 8),
      _SwitchRow(
        switchKey: const Key('source-edit-enabled-explore'),
        title: '参与发现',
        description: '书源没有声明发现规则时，这个开关不会产生分类。',
        value: _enabledExplore,
        onChanged: (value) => setState(() => _enabledExplore = value),
      ),
    ],
  );

  Widget _buildJsonSection(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '直接编辑原始 JSON。保存时整体生效；本项目不认识的字段会原样保留，方便在客户端之间互相导入。',
        style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.7),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('source-edit-json'),
        controller: _raw,
        minLines: 12,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.6,
        ),
        decoration: const InputDecoration(hintText: '{}'),
      ),
    ],
  );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: fieldKey,
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(hintText: hint, isDense: true),
        ),
      ],
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.switchKey,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        Switch(
          key: switchKey,
          value: value,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.ink,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('source-edit-error'),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFDECEC),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      message,
      style: const TextStyle(fontSize: 12, color: Color(0xFFB54444)),
    ),
  );
}
