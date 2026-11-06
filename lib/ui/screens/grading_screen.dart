/// 批改页（老师专用）：B 组。
///
/// 分三组列表：已交 / 未交 / 迟交。点一个已交或迟交的学生进批改：
/// 拍照模式看照片大图，App 内做题模式看每题答案与自动分；
/// 打分按作业的打分方式二选一输入（100 分制或优良中差），另有评语文本框，
/// 提交后该学生状态变已批改。
library;

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/assignment_service.dart';
import '../../services/submission_service.dart';
import '../../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class GradingScreen extends StatefulWidget {
  final Assignment assignment;

  const GradingScreen({super.key, required this.assignment});

  @override
  State<GradingScreen> createState() => _GradingScreenState();
}

class _GradingScreenState extends State<GradingScreen> {
  final _submissionService = SubmissionService();
  bool _loading = true;
  String? _error;
  List<ClassMember> _members = [];
  List<Submission> _submissions = [];

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
      final memberRows = await SupabaseService.client
          .from('class_members')
          .select()
          .eq('class_id', _assignment.classId)
          .order('joined_at', ascending: true);
      final members = (memberRows as List)
          .map((e) => ClassMember.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // 班级成员表里没有姓名时，从 profiles 表补真实姓名。
      final missingNameIds = members
          .where((m) => (m.studentName ?? '').isEmpty)
          .map((m) => m.studentId)
          .toList();
      final names = <String, String>{};
      if (missingNameIds.isNotEmpty) {
        final profileRows = await SupabaseService.client
            .from('profiles')
            .select('id, real_name')
            .inFilter('id', missingNameIds);
        for (final r in (profileRows as List)) {
          names[(r['id'] ?? '').toString()] =
              (r['real_name'] ?? '').toString();
        }
      }
      final submissions =
          await _submissionService.submissionsOf(_assignment.id);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _members = members
            .map((m) => ClassMember(
                  id: m.id,
                  classId: m.classId,
                  studentId: m.studentId,
                  studentName: (m.studentName ?? '').isNotEmpty
                      ? m.studentName
                      : names[m.studentId],
                  joinedAt: m.joinedAt,
                ))
            .toList();
        _submissions = submissions;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  String _nameOf(ClassMember member) {
    final name = (member.studentName ?? '').trim();
    return name.isEmpty ? '学生' : name;
  }

  String _nameOfSubmission(Submission submission) {
    final name = (submission.studentName ?? '').trim();
    if (name.isNotEmpty) return name;
    for (final m in _members) {
      if (m.studentId == submission.studentId) return _nameOf(m);
    }
    return '学生';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('批改：${_assignment.title}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _load,
          ),
        ],
      ),
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
              : _buildGroups(),
    );
  }

  Widget _buildGroups() {
    final submittedByStudent = {
      for (final s in _submissions) s.studentId: s,
    };
    // 已交组：按时交的（含已批改的）；迟交组：迟交的（含已批改的）。
    final onTime = _submissions
        .where((s) => !s.isLate)
        .toList(growable: false);
    final late =
        _submissions.where((s) => s.isLate).toList(growable: false);
    final unsubmitted = _members
        .where((m) => !submittedByStudent.containsKey(m.studentId))
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _groupHeader('已交', onTime.length),
        if (onTime.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('暂无按时提交的学生。'),
          )
        else
          for (final s in onTime) _submissionTile(s),
        _groupHeader('迟交', late.length),
        if (late.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('暂无迟交的学生。'),
          )
        else
          for (final s in late) _submissionTile(s),
        _groupHeader('未交', unsubmitted.length),
        if (unsubmitted.isEmpty)
          const Text('全班都交了。')
        else
          for (final m in unsubmitted)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(_nameOf(m)),
                trailing: const Chip(
                  label: Text('未交'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
      ],
    );
  }

  Widget _groupHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        '$title（$count 人）',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _submissionTile(Submission submission) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(_nameOfSubmission(submission)),
        subtitle: Text(
          _assignment.mode == AssignmentMode.quiz &&
                  submission.autoScore != null
              ? '自动得分：${submission.autoScore} 分'
              : _assignment.mode == AssignmentMode.photo
                  ? '已上传 ${submission.photoUrls.length} 张照片'
                  : '已提交',
        ),
        trailing: Chip(
          label: Text(submission.statusLabel),
          backgroundColor: submission.isGraded
              ? Colors.blue.withOpacity(0.12)
              : AppTheme.primary.withOpacity(0.12),
          labelStyle: TextStyle(
            color:
                submission.isGraded ? Colors.blue : AppTheme.primary,
            fontSize: 12,
          ),
          visualDensity: VisualDensity.compact,
        ),
        onTap: () async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => _GradingDetailScreen(
                assignment: _assignment,
                submission: submission,
                studentName: _nameOfSubmission(submission),
              ),
            ),
          );
          _load();
        },
      ),
    );
  }
}

/// 单个学生的批改详情页（与批改列表放同一文件）。
class _GradingDetailScreen extends StatefulWidget {
  final Assignment assignment;
  final Submission submission;
  final String studentName;

  const _GradingDetailScreen({
    required this.assignment,
    required this.submission,
    required this.studentName,
  });

  @override
  State<_GradingDetailScreen> createState() => _GradingDetailScreenState();
}

class _GradingDetailScreenState extends State<_GradingDetailScreen> {
  final _submissionService = SubmissionService();
  final _scoreController = TextEditingController();
  final _commentController = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Question> _questions = [];
  Grade? _existingGrade;
  String? _selectedGradeLabel;
  bool _submitting = false;

  Assignment get _assignment => widget.assignment;
  Submission get _submission => widget.submission;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scoreController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var questions = <Question>[];
      if (_assignment.mode == AssignmentMode.quiz) {
        questions =
            await AssignmentService().questionsOf(_assignment.id);
      }
      final grade = await _submissionService
          .gradeOfSubmission(_submission.id);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _existingGrade = grade;
        _selectedGradeLabel = grade?.gradeLabel;
        if (grade?.score != null) {
          _scoreController.text = grade!.score.toString();
        }
        if (grade?.comment != null) {
          _commentController.text = grade!.comment!;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  void _viewPhoto(String url) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('图片加载失败，请检查网络后重试。'),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: '关闭',
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitGrade() async {
    final alreadyGraded = _existingGrade != null;
    if (alreadyGraded) return;
    int? score;
    if (_assignment.gradingMode == GradingMode.score100) {
      score = int.tryParse(_scoreController.text.trim());
      if (score == null || score < 0 || score > 100) {
        _showMessage('请填写 0 到 100 之间的分数');
        return;
      }
    } else if (_selectedGradeLabel == null) {
      _showMessage('请选择 优、良、中、差 之一');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _submissionService.gradeSubmission(
        submissionId: _submission.id,
        score: score,
        gradeLabel: _selectedGradeLabel,
        comment: _commentController.text,
      );
      if (!mounted) return;
      _showMessage('批改完成');
      Navigator.of(context).pop(true);
    } catch (e) {
      _showMessage('批改失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('批改：${widget.studentName}')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_assignment.mode == AssignmentMode.photo)
                        _photoSection()
                      else
                        _quizSection(),
                      const SizedBox(height: 16),
                      _gradeInputSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _photoSection() {
    final urls = _submission.photoUrls;
    if (urls.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('该学生没有上传照片。'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '照片（${urls.length} 张，点开放大）',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: urls.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => _viewPhoto(urls[index]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      urls[index],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _quizSection() {
    final answers = _submission.answers;
    final needsReview = _submissionService.needsReviewQuestions(
      _questions,
      answers.map((k, v) => MapEntry(k, v.toString())),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '自动得分：${_submission.autoScore ?? 0} 分'
              '${needsReview.isNotEmpty ? '（其中 ${needsReview.length} 道填空题需复核）' : ''}',
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _questions.length; i++)
          _answerCard(_questions[i], i, needsReview.contains(_questions[i].id)),
      ],
    );
  }

  Widget _answerCard(Question question, int index, bool needsReview) {
    final mine = (_submission.answers[question.id] ?? '').toString();
    final correct = question.isChoice
        ? SubmissionService.choiceCorrectText(question)
        : question.answer;
    final isCorrect = question.isChoice
        ? SubmissionService.isChoiceCorrect(question, mine)
        : SubmissionService.normalizeFillAnswer(mine) ==
            SubmissionService.normalizeFillAnswer(question.answer);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '第 ${index + 1} 题',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  isCorrect ? '答对（${question.points} 分）' : '未得分',
                  style: TextStyle(
                    color: isCorrect ? AppTheme.primary : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(question.stem),
            const SizedBox(height: 8),
            Text('学生答案：${mine.isEmpty ? '未作答' : mine}'),
            Text('标准答案：$correct'),
            if (needsReview)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '这道填空题答案与标准答案不一致，需老师复核。',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gradeInputSection() {
    final alreadyGraded = _existingGrade != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '打分',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (alreadyGraded) ...[
              Text('批改结果：${_existingGrade!.displayResult}'),
              if (_existingGrade!.comment != null &&
                  _existingGrade!.comment!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('评语：${_existingGrade!.comment}'),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '已批改，不能重复批改。',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ] else ...[
              if (_assignment.gradingMode == GradingMode.score100)
                TextField(
                  controller: _scoreController,
                  decoration: const InputDecoration(
                    labelText: '分数（0 到 100）',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                )
              else
                Wrap(
                  spacing: 8,
                  children: [
                    for (final label in ['优', '良', '中', '差'])
                      ChoiceChip(
                        label: Text(label),
                        selected: _selectedGradeLabel == label,
                        onSelected: (_) {
                          setState(() => _selectedGradeLabel = label);
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _commentController,
                decoration: const InputDecoration(
                  labelText: '评语',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submitGrade,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(_submitting ? '提交中…' : '提交批改'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
