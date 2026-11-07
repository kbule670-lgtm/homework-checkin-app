/// 班级列表页：老师建班，学生输邀请码进班。
///
/// 列表每项显示班级名、科目、邀请码、人数；点一项进班级详情。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../services/class_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'class_detail_screen.dart';

class ClassesScreen extends StatefulWidget {
  final Profile? profile;

  const ClassesScreen({super.key, this.profile});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  final _service = ClassService();
  final _inviteController = TextEditingController();
  final _nameController = TextEditingController();
  final _subjectController = TextEditingController();

  List<SchoolClass> _classes = <SchoolClass>[];
  Map<String, int> _memberCounts = <String, int>{};
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inviteController.dispose();
    _nameController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  bool get _isTeacher => widget.profile?.isTeacher ?? false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 各班人数互不依赖，并行取；全部请求加 15 秒上限，超时不再无限转圈。
      final classes =
          await _service.myClasses().timeout(const Duration(seconds: 15));
      final memberLists = await Future.wait(
        classes.map((c) => _service.membersOf(c.id)),
      ).timeout(const Duration(seconds: 15));
      final counts = <String, int>{
        for (var i = 0; i < classes.length; i++)
          classes[i].id: memberLists[i].length,
      };
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _memberCounts = counts;
      });
    } on TimeoutException {
      if (mounted) {
        showAppSnackBar(context, '加载超时，请检查网络后重试', isError: true);
      }
    } on StateError catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, '班级加载失败，请稍后重试', isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createClass() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showAppSnackBar(context, '班级名不能为空', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final schoolClass = await _service.createClass(
        name: name,
        subject: _subjectController.text.trim().isEmpty
            ? null
            : _subjectController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _nameController.clear();
      _subjectController.clear();
      showAppSnackBar(context, '建班成功，邀请码是 ${schoolClass.inviteCode}');
      await _load();
    } on StateError catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } catch (_) {
      if (mounted) showAppSnackBar(context, '建班失败，请稍后重试', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinClass() async {
    final code = _inviteController.text.trim();
    if (code.isEmpty) {
      showAppSnackBar(context, '请先输入邀请码', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final schoolClass = await _service.joinClass(code);
      if (!mounted) return;
      _inviteController.clear();
      showAppSnackBar(context, '已加入 ${schoolClass.name}');
      await _load();
    } on StateError catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } catch (_) {
      if (mounted) showAppSnackBar(context, '加入失败，请稍后重试', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 左滑解散班级：滑出红色“解散”，松手先弹确认框，点确认才真的解散。
  Future<bool> _confirmDissolve(SchoolClass schoolClass) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('解散班级'),
          content: Text(
            '解散“${schoolClass.name}”后，该班的作业、学生提交和批改记录都会删除，不可恢复。确定要解散吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('确认解散'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _dissolveClass(SchoolClass schoolClass) async {
    try {
      await _service.deleteClass(schoolClass.id);
      if (!mounted) return;
      showAppSnackBar(context, '班级已解散');
      _load();
    } on StateError catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } catch (_) {
      if (mounted) showAppSnackBar(context, '解散失败，请稍后重试', isError: true);
    }
  }

  Widget _classCard(SchoolClass schoolClass) {
    return WeChatCard(
      onTap: () async {
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => ClassDetailScreen(
              schoolClass: schoolClass,
              profile: widget.profile,
            ),
          ),
        );
        if (changed == true) _load();
      },
      child: Row(
        children: <Widget>[
          NameAvatar(name: schoolClass.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  schoolClass.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (schoolClass.subject != null &&
                        schoolClass.subject!.isNotEmpty)
                      schoolClass.subject!,
                    '邀请码 ${schoolClass.inviteCode}',
                    '${_memberCounts[schoolClass.id] ?? 0} 人',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '复制邀请码',
            icon: const Icon(
              Icons.copy,
              size: 20,
              color: AppTheme.textSecondary,
            ),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: schoolClass.inviteCode),
              );
              if (context.mounted) {
                showAppSnackBar(context, '邀请码已复制');
              }
            },
          ),
          const Icon(
            Icons.chevron_right,
            color: AppTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  void _showCreateDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建班级'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '班级名',
                hintText: '例如：高二 15 班',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectController,
              decoration: const InputDecoration(
                labelText: '科目（可选）',
                hintText: '例如：数学',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: _busy ? null : _createClass,
            child: const Text('建班'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingView(message: '班级加载中…');
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: <Widget>[
          if (_isTeacher)
            WeChatCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    '新建班级',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '建好班把邀请码发给学生，学生输码就能进班。',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _showCreateDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('新建班级'),
                  ),
                ],
              ),
            )
          else
            WeChatCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    '加入班级',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _inviteController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            hintText: '输入 6 位邀请码',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _busy ? null : _joinClass,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(72, 48),
                        ),
                        child: const Text('加入'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SectionTitle(title: '我的班级'),
          if (_classes.isEmpty)
            const EmptyView(
              icon: Icons.group_outlined,
              message: '还没有班级',
            )
          else
            for (final schoolClass in _classes)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _isTeacher
                    ? Dismissible(
                        key: ValueKey('class_${schoolClass.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '解散',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                        confirmDismiss: (_) =>
                            _confirmDissolve(schoolClass),
                        onDismissed: (_) => _dissolveClass(schoolClass),
                        child: _classCard(schoolClass),
                      )
                    : _classCard(schoolClass),
              ),
        ],
      ),
    );
  }
}
