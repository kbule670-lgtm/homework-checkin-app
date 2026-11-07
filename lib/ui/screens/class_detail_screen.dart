/// 班级详情页：班级信息、成员列表（老师可见真实姓名）、该班作业入口。
/// 该班作业入口进 B 组的 AssignmentsScreen（无参构造，页内可按班级筛选）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../services/class_service.dart';
import '../../services/supabase_service.dart';
import 'assignments_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ClassDetailScreen extends StatefulWidget {
  final SchoolClass schoolClass;
  final Profile? profile;

  const ClassDetailScreen({
    super.key,
    required this.schoolClass,
    this.profile,
  });

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  final _service = ClassService();
  List<ClassMember> _members = <ClassMember>[];
  bool _loading = true;
  bool _deleting = false;

  /// 只有建班老师本人才看到解散入口：优先按班级的 teacherId 认，
  /// 拿不到登录用户时退回传进来的 profile 身份。
  bool get _isOwner {
    final uid = SupabaseService.client.auth.currentUser?.id ?? '';
    if (uid.isNotEmpty) return widget.schoolClass.teacherId == uid;
    return widget.profile?.isTeacher ?? false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final members = await _service.membersOf(widget.schoolClass.id);
      if (!mounted) return;
      setState(() => _members = members);
    } on StateError catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } catch (_) {
      if (mounted) showAppSnackBar(context, '成员加载失败', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmDissolve() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('解散班级'),
          content: Text(
            '解散“${widget.schoolClass.name}”后，该班的作业、学生提交和批改记录都会删除，不可恢复。确定要解散吗？',
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
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _service.deleteClass(widget.schoolClass.id);
      if (!mounted) return;
      showAppSnackBar(context, '班级已解散');
      Navigator.of(context).pop(true);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showAppSnackBar(context, e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showAppSnackBar(context, '解散失败，请稍后重试', isError: true);
    }
  }

  Future<void> _confirmRemove(ClassMember member) async {
    final name = member.studentName ?? '该学生';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('移出班级'),
          content: Text(
            '确定把 $name 移出“${widget.schoolClass.name}”吗？移出后他就看不到这个班的作业了，已交的记录不受影响。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('确认移出'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.removeMember(widget.schoolClass.id, member.studentId);
      if (!mounted) return;
      showAppSnackBar(context, '已把 $name 移出班级');
      _load();
    } on StateError catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, '移出失败，请稍后重试', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final schoolClass = widget.schoolClass;
    return Scaffold(
      appBar: AppBar(title: Text(schoolClass.name)),
      body: _loading
          ? const LoadingView(message: '成员加载中…')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                WeChatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          NameAvatar(name: schoolClass.name, size: 52),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  schoolClass.name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  schoolClass.subject ?? '未填科目',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              '邀请码',
                              style: TextStyle(fontSize: 15),
                            ),
                          ),
                          Text(
                            schoolClass.inviteCode,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: schoolClass.inviteCode),
                              );
                              if (context.mounted) {
                                showAppSnackBar(context, '邀请码已复制');
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(64, 36),
                            ),
                            child: const Text('复制'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                WeChatCard(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AssignmentsScreen(),
                      ),
                    );
                  },
                  child: const Row(
                    children: <Widget>[
                      Icon(
                        Icons.assignment_outlined,
                        color: AppTheme.primary,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text('查看本班作业', style: TextStyle(fontSize: 16)),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
                SectionTitle(title: '成员（${_members.length} 人）'),
                if (_members.isEmpty)
                  const EmptyView(
                    icon: Icons.person_outline,
                    message: '还没有学生加入，把邀请码发给学生吧',
                  )
                else
                  WeChatCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        for (var i = 0; i < _members.length; i++) ...<Widget>[
                          ListTile(
                            leading: NameAvatar(
                              name: _members[i].studentName ?? '学生',
                              size: 40,
                            ),
                            title: Text(
                              _members[i].studentName ?? '学生',
                            ),
                            subtitle: Text(
                              '加入时间 ${_members[i].joinedAt.year}-'
                              '${_members[i].joinedAt.month.toString().padLeft(2, '0')}-'
                              '${_members[i].joinedAt.day.toString().padLeft(2, '0')}',
                            ),
                            trailing: _isOwner
                                ? TextButton(
                                    onPressed: () =>
                                        _confirmRemove(_members[i]),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    child: const Text('移出'),
                                  )
                                : null,
                          ),
                          if (i != _members.length - 1)
                            const Divider(height: 1, indent: 68),
                        ],
                      ],
                    ),
                  ),
                if (_isOwner) ...[
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: _deleting ? null : _confirmDissolve,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_deleting ? '解散中…' : '解散班级'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '解散后该班的作业、提交和批改记录都会删除，不可恢复。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
    );
  }
}

