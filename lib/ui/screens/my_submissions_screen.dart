/// 我的提交 tab（学生专用）：只列我交过的作业和批改结果。
///
/// 跟“作业” tab 的区别：作业 tab 是老师布置给我的全部作业（包括没交的，
/// 点进去做题或拍照上传）；我的提交 tab 只看我已经交了的——每行写状态
/// （已交 / 迟交 / 已批改）和分数、评语，点进去看这份作业的详情。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../services/assignment_service.dart';
import '../../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'assignment_detail_screen.dart';

class MySubmissionsScreen extends StatefulWidget {
  const MySubmissionsScreen({super.key});

  @override
  State<MySubmissionsScreen> createState() => _MySubmissionsScreenState();
}

class _MySubmissionsScreenState extends State<MySubmissionsScreen> {
  bool _loading = true;
  String? _error;
  List<Submission> _submissions = [];
  Map<String, Assignment> _assignmentsById = {};
  Map<String, Grade> _gradesBySubmission = {};

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
    if (uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _submissions = const [];
        _assignmentsById = const {};
        _gradesBySubmission = const {};
      });
      return;
    }
    final rows = await SupabaseService.client
        .from('submissions')
        .select()
        .eq('student_id', uid)
        .order('submitted_at', ascending: false);
    final submissions = (rows as List)
        .map((e) => Submission.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (submissions.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _submissions = const [];
        _assignmentsById = const {};
        _gradesBySubmission = const {};
      });
      return;
    }
    final assignmentIds =
        submissions.map((s) => s.assignmentId).toSet().toList();
    final assignmentRows = await SupabaseService.client
        .from('assignments')
        .select()
        .inFilter('id', assignmentIds);
    final assignments = (assignmentRows as List)
        .map((e) => Assignment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    // 已批改的才查批改记录。
    final gradedIds =
        submissions.where((s) => s.isGraded).map((s) => s.id).toList();
    final grades = <String, Grade>{};
    if (gradedIds.isNotEmpty) {
      final gradeRows = await SupabaseService.client
          .from('grades')
          .select()
          .inFilter('submission_id', gradedIds);
      for (final row in (gradeRows as List)) {
        final g = Grade.fromJson(Map<String, dynamic>.from(row));
        grades[g.submissionId] = g;
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _submissions = submissions;
      _assignmentsById = {for (final a in assignments) a.id: a};
      _gradesBySubmission = grades;
    });
  }

  Color _statusColor(Submission submission) {
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
    if (_submissions.isEmpty) {
      return const EmptyView(
        icon: Icons.outbox_outlined,
        message: '你还没有提交过作业',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _submissions.length,
        itemBuilder: (context, index) {
          final submission = _submissions[index];
          final assignment = _assignmentsById[submission.assignmentId];
          final grade = _gradesBySubmission[submission.id];
          final submittedText = DateFormat('yyyy年MM月dd日 HH:mm')
              .format(submission.submittedAt);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: Text(
                assignment?.title ?? '作业',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('提交时间：$submittedText'),
                  if (grade != null) ...[
                    const SizedBox(height: 4),
                    Text('成绩：${grade.displayResult}'),
                    if (grade.comment != null && grade.comment!.isNotEmpty)
                      Text('老师评语：${grade.comment}'),
                  ],
                  const SizedBox(height: 6),
                  Chip(
                    label: Text(submission.statusLabel),
                    backgroundColor:
                        _statusColor(submission).withOpacity(0.12),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _statusColor(submission),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: assignment == null
                  ? null
                  : () async {
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => AssignmentDetailScreen(
                            assignment: assignment,
                          ),
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
