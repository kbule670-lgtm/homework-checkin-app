/// 作业详情页：B 组。
///
/// 学生：看作业详情、提交入口、我的提交状态、批改后的分数和评语。
/// 老师：看该作业统计（已交 X / 共 Y、迟交 Z）与提交列表入口。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../services/submission_service.dart';
import '../../services/supabase_service.dart';
import '../../services/assignment_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'grading_screen.dart';
import 'quiz_screen.dart';
import 'submit_photo_screen.dart';

class AssignmentDetailScreen extends StatefulWidget {
  final Assignment assignment;

  const AssignmentDetailScreen({super.key, required this.assignment});

  @override
  State<AssignmentDetailScreen> createState() =>
      _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  final _submissionService = SubmissionService();
  bool _loading = true;
  String? _error;
  bool _isTeacher = false;
  Submission? _mySubmission;
  Grade? _myGrade;
  List<Submission> _submissions = [];
  int _memberCount = 0;

  Assignment get _assignment => widget.assignment;

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
    var isTeacher = false;
    if (uid.isNotEmpty) {
      final row = await SupabaseService.client
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      isTeacher = row != null && row['role'] == 'teacher';
    }

    Submission? mySubmission;
    Grade? myGrade;
    var submissions = <Submission>[];
    var memberCount = 0;
    if (isTeacher) {
      // 提交列表与班级人数互不依赖，并行取。
      final results = await Future.wait<dynamic>([
        _submissionService.submissionsOf(_assignment.id),
        SupabaseService.client
            .from('class_members')
            .select('id')
            .eq('class_id', _assignment.classId),
      ]);
      submissions = results[0] as List<Submission>;
      memberCount = (results[1] as List).length;
    } else if (uid.isNotEmpty) {
      final row = await SupabaseService.client
          .from('submissions')
          .select()
          .eq('assignment_id', _assignment.id)
          .eq('student_id', uid)
          .maybeSingle();
      if (row != null) {
        mySubmission =
            Submission.fromJson(Map<String, dynamic>.from(row));
        myGrade = await _submissionService
            .gradeOfSubmission(mySubmission.id);
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _isTeacher = isTeacher;
      _mySubmission = mySubmission;
      _myGrade = myGrade;
      _submissions = submissions;
      _memberCount = memberCount;
    });
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _goSubmit() async {
    if (_mySubmission?.isGraded == true) {
      _showMessage('已批改，不能重交');
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _assignment.mode == AssignmentMode.photo
            ? SubmitPhotoScreen(assignment: _assignment)
            : QuizScreen(assignment: _assignment),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作业详情')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _infoCard(),
                      const SizedBox(height: 16),
                      if (_isTeacher) _teacherStatsCard() else _studentCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _infoCard() {
    final deadlineText =
        DateFormat('yyyy年MM月dd日 HH:mm').format(_assignment.deadline);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _assignment.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text(_assignment.modeLabel),
                  backgroundColor: AppTheme.primary.withOpacity(0.12),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(_assignment.gradingLabel),
                  visualDensity: VisualDensity.compact,
                ),
                if (_assignment.isOverdue)
                  const Chip(
                    label: Text('已截止'),
                    backgroundColor: Colors.red,
                    labelStyle: TextStyle(color: Colors.white),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _assignment.description.isEmpty
                  ? '暂无说明'
                  : _assignment.description,
            ),
            const SizedBox(height: 12),
            Text(
              '截止时间：$deadlineText',
              style: TextStyle(
                color: _assignment.isOverdue ? Colors.red : null,
              ),
            ),
            if (_assignment.isOverdue)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '已过截止时间，现在提交会记为迟交。',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _studentCard() {
    final submission = _mySubmission;
    final grade = _myGrade;
    final graded = submission?.isGraded == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '我的提交',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (submission == null)
              const Text('还没有提交。')
            else ...[
              Text('状态：${submission.statusLabel}'),
              Text(
                '提交时间：${DateFormat('yyyy年MM月dd日 HH:mm').format(submission.submittedAt)}',
              ),
              if (submission.isLate)
                const Text(
                  '本次提交已过截止时间，记为迟交。',
                  style: TextStyle(color: Colors.orange),
                ),
              if (_assignment.mode == AssignmentMode.photo)
                Text('已上传 ${submission.photoUrls.length} 张照片'),
              if (_assignment.mode == AssignmentMode.quiz &&
                  submission.autoScore != null)
                Text('自动得分：${submission.autoScore} 分'),
            ],
            if (graded && grade != null) ...[
              const Divider(height: 24),
              const Text(
                '批改结果',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('成绩：${grade.displayResult}'),
              if (grade.comment != null && grade.comment!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('老师评语：${grade.comment}'),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: graded ? null : _goSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                graded
                    ? '已批改，不能重交'
                    : submission == null
                        ? (_assignment.mode == AssignmentMode.photo
                            ? '拍照上传'
                            : '开始做题')
                        : '重新提交',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teacherStatsCard() {
    final submittedCount = _submissions.length;
    final lateCount = _submissions.where((s) => s.isLate).length;
    final gradedCount =
        _submissions.where((s) => s.status == SubmissionStatus.graded).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '提交统计',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('已交', '$submittedCount / $_memberCount'),
                _statItem('迟交', '$lateCount 人'),
                _statItem('已批改', '$gradedCount 人'),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => GradingScreen(assignment: _assignment),
                  ),
                );
                _load();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('查看提交与批改'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
