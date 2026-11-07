/// 作业列表页：B 组。
///
/// 按班级筛选、按截止时间排序；每条作业显示模式角标（拍照上传 / App 内做题）
/// 与状态角标（学生：未交 / 已交 / 迟交 / 已批改）。老师右下角有新建作业入口。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../services/assignment_service.dart';
import '../../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'assignment_create_screen.dart';
import 'assignment_detail_screen.dart';

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  final _assignmentService = AssignmentService();
  bool _loading = true;
  String? _error;
  bool _isTeacher = false;
  List<Assignment> _assignments = [];
  List<SchoolClass> _classes = [];
  Map<String, Submission> _mySubmissions = {};
  String? _selectedClassId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!SupabaseService.isConfigured) {
      setState(() {
        _loading = false;
        _error = kSupabaseNotConfiguredMessage;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 全部请求加 15 秒上限：弱网时不再无限转圈，超时给重试。
      await _fetchAll().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载超时，请检查网络后重试';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  Future<void> _fetchAll() async {
    final uid = SupabaseService.client.auth.currentUser?.id ?? '';
    Profile? profile;
    if (uid.isNotEmpty) {
      final row = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row != null) {
        profile = Profile.fromJson(Map<String, dynamic>.from(row));
      }
    }
    final isTeacher = profile?.isTeacher ?? false;

    // 班级列表与作业列表互不依赖，并行取，不再一个一个等。
    final results = await Future.wait<dynamic>([
      profile != null
          ? _loadClassesFor(profile, isTeacher)
          : Future<List<SchoolClass>>.value(<SchoolClass>[]),
      _assignmentService.myAssignments(),
    ]);
    final classes = results[0] as List<SchoolClass>;
    final assignments = results[1] as List<Assignment>;

    final mySubmissions = <String, Submission>{};
    if (!isTeacher && uid.isNotEmpty && assignments.isNotEmpty) {
      final assignmentIds = assignments.map((a) => a.id).toList();
      final rows = await SupabaseService.client
          .from('submissions')
          .select()
          .eq('student_id', uid)
          .inFilter('assignment_id', assignmentIds);
      for (final row in (rows as List)) {
        final s = Submission.fromJson(Map<String, dynamic>.from(row));
        mySubmissions[s.assignmentId] = s;
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _isTeacher = isTeacher;
      _classes = classes;
      _assignments = assignments;
      _mySubmissions = mySubmissions;
    });
  }

  Future<List<SchoolClass>> _loadClassesFor(
      Profile profile, bool isTeacher) async {
    final classes = <SchoolClass>[];
    if (isTeacher) {
      final rows = await SupabaseService.client
          .from('classes')
          .select()
          .eq('teacher_id', profile.id)
          .order('created_at', ascending: true);
      classes.addAll((rows as List).map(
          (e) => SchoolClass.fromJson(Map<String, dynamic>.from(e))));
    } else {
      final memberRows = await SupabaseService.client
          .from('class_members')
          .select('class_id')
          .eq('student_id', profile.id);
      final classIds = (memberRows as List)
          .map((e) => e['class_id'].toString())
          .toList();
      if (classIds.isNotEmpty) {
        final rows = await SupabaseService.client
            .from('classes')
            .select()
            .inFilter('id', classIds)
            .order('created_at', ascending: true);
        classes.addAll((rows as List).map(
            (e) => SchoolClass.fromJson(Map<String, dynamic>.from(e))));
      }
    }
    return classes;
  }

  List<Assignment> get _filtered {
    final list = _selectedClassId == null
        ? _assignments
        : _assignments.where((a) => a.classId == _selectedClassId).toList();
    list.sort((a, b) => a.deadline.compareTo(b.deadline));
    return list;
  }

  String _className(String classId) {
    for (final c in _classes) {
      if (c.id == classId) return c.name;
    }
    return '班级';
  }

  String _statusText(Assignment assignment) {
    final submission = _mySubmissions[assignment.id];
    if (submission == null) {
      return assignment.isOverdue ? '已截止，未交' : '未交';
    }
    return submission.statusLabel;
  }

  Color _statusColor(Assignment assignment) {
    final submission = _mySubmissions[assignment.id];
    if (submission == null) {
      return assignment.isOverdue ? Colors.red : Colors.orange;
    }
    switch (submission.status) {
      case SubmissionStatus.submitted:
        return AppTheme.primary;
      case SubmissionStatus.late:
        return Colors.orange;
      case SubmissionStatus.graded:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 不要在这里再放 AppBar：HomeScreen 已经有一个显示当前 tab 名的 AppBar，
    // 这里再放一个会上下出现两个“作业”。刷新用下拉刷新（RefreshIndicator）。
    return Scaffold(
      floatingActionButton: _isTeacher
          ? Padding(
              // 本页是嵌在 HomeScreen 里的二级 Scaffold，页面底部会伸到
              // 底部栏下面（extendBody），加号不垫高会被底部栏盖住点不着。
              padding: const EdgeInsets.only(bottom: 108),
              child: FloatingActionButton(
                onPressed: () async {
                  final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const AssignmentCreateScreen(),
                    ),
                  );
                  if (created == true) _load();
                },
                tooltip: '新建作业',
                child: const Icon(Icons.add),
              ),
            )
          : null,
      body: Column(
        children: [
          if (_classes.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<String?>(
                value: _selectedClassId,
                decoration: const InputDecoration(
                  labelText: '班级筛选',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部班级'),
                  ),
                  for (final c in _classes)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name),
                    ),
                ],
                onChanged: (value) {
                  setState(() => _selectedClassId = value);
                },
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return const EmptyView(icon: Icons.assignment_outlined, message: '暂无作业');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final assignment = list[index];
          final deadlineText =
              DateFormat('yyyy年MM月dd日 HH:mm').format(assignment.deadline);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: Text(
                assignment.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(_className(assignment.classId)),
                  Text(
                    '截止：$deadlineText',
                    style: TextStyle(
                      color: assignment.isOverdue ? Colors.red : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text(assignment.modeLabel),
                        backgroundColor:
                            AppTheme.primary.withOpacity(0.12),
                        labelStyle: const TextStyle(fontSize: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (!_isTeacher)
                        Chip(
                          label: Text(_statusText(assignment)),
                          backgroundColor: _statusColor(assignment)
                              .withOpacity(0.12),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: _statusColor(assignment),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        AssignmentDetailScreen(assignment: assignment),
                  ),
                );
                _load();
              },
            ),
          );
        },
      ),
    );
  }
}
