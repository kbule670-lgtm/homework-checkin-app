/// 班级详情页：班级信息、成员列表（老师可见真实姓名）、该班作业入口。
/// 该班作业入口进 B 组的 AssignmentsScreen（无参构造，页内可按班级筛选）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../services/class_service.dart';
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
                          ),
                          if (i != _members.length - 1)
                            const Divider(height: 1, indent: 68),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

