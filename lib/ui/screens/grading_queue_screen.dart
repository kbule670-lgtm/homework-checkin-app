/// 批改 tab（老师专用）：按作业列出提交统计，点进去逐份批改。
///
/// 跟“作业” tab 的区别：作业 tab 是我布置过的作业清单（看标题、截止时间、
/// 点进去看详情）；批改 tab 是待办队列——每行直接写“已交 x / 共 y 人，
/// 待批改 z 份”，点进去就是批改页，不用先绕到详情再点“查看提交与批改”。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../services/assignment_service.dart';
import '../../services/class_service.dart';
import '../../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'grading_screen.dart';

class GradingQueueScreen extends StatefulWidget {
  const GradingQueueScreen({super.key});

  @override
  State<GradingQueueScreen> createState() => _GradingQueueScreenState();
}

class _GradingQueueScreenState extends State<GradingQueueScreen> {
  final _assignmentService = AssignmentService();
  final _classService = ClassService();
  bool _loading = true;
  String? _error;
  List<Assignment> _assignments = [];
  Map<String, SchoolClass> _classesById = {};
  Map<String, int> _submittedByAssignment = {};
  Map<String, int> _ungradedByAssignment = {};
  Map<String, int> _memberCountByClass = {};

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
    final assignments = await _assignmentService.myAssignments();
    if (assignments.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _assignments = const [];
        _classesById = const {};
        _submittedByAssignment = const {};
        _ungradedByAssignment = const {};
        _memberCountByClass = const {};
      });
      return;
    }
    final assignmentIds = assignments.map((a) => a.id).toList();
    final classIds = assignments.map((a) => a.classId).toSet().toList();
    // 班级、提交、班级人数互不依赖，并行取。
    final results = await Future.wait<dynamic>([
      _classService.myClasses(),
      SupabaseService.client
          .from('submissions')
          .select()
          .inFilter('assignment_id', assignmentIds),
      SupabaseService.client
          .from('class_members')
          .select('class_id')
          .inFilter('class_id', classIds),
    ]);
    final classes = results[0] as List<SchoolClass>;
    final submissionRows = results[1] as List;
    final memberRows = results[2] as List;
    final submitted = <String, int>{};
    final ungraded = <String, int>{};
    for (final row in submissionRows) {
      final s = Submission.fromJson(Map<String, dynamic>.from(row));
      submitted[s.assignmentId] = (submitted[s.assignmentId] ?? 0) + 1;
      if (s.status != SubmissionStatus.graded) {
        ungraded[s.assignmentId] = (ungraded[s.assignmentId] ?? 0) + 1;
      }
    }
    final memberCount = <String, int>{};
    for (final row in memberRows) {
      final classId = (row['class_id'] ?? '').toString();
      memberCount[classId] = (memberCount[classId] ?? 0) + 1;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _assignments = assignments;
      _classesById = {for (final c in classes) c.id: c};
      _submittedByAssignment = submitted;
      _ungradedByAssignment = ungraded;
      _memberCountByClass = memberCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 不要在这里再放 AppBar：HomeScreen 已经有一个显示当前 tab 名的 AppBar。
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
    if (_assignments.isEmpty) {
      return const EmptyView(
        icon: Icons.checklist_outlined,
        message: '暂无需要批改的作业',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _assignments.length,
        itemBuilder: (context, index) {
          final assignment = _assignments[index];
          final className =
              _classesById[assignment.classId]?.name ?? '班级';
          final submitted = _submittedByAssignment[assignment.id] ?? 0;
          final total = _memberCountByClass[assignment.classId] ?? 0;
          final ungraded = _ungradedByAssignment[assignment.id] ?? 0;
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
                  Text('$className · 截止：$deadlineText'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text('已交 $submitted / 共 $total 人'),
                        backgroundColor: AppTheme.primary.withOpacity(0.12),
                        labelStyle: const TextStyle(fontSize: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (ungraded > 0)
                        Chip(
                          label: Text('待批改 $ungraded 份'),
                          backgroundColor: Colors.red.withOpacity(0.12),
                          labelStyle: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                          visualDensity: VisualDensity.compact,
                        )
                      else
                        const Chip(
                          label: Text('全部已批改'),
                          backgroundColor: Colors.transparent,
                          labelStyle: TextStyle(fontSize: 12),
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
                    builder: (_) => GradingScreen(assignment: assignment),
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
