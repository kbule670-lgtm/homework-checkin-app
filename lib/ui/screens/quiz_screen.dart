/// App 内做题页：B 组。
///
/// 逐题作答：选择题点选项，填空题输文本。交卷时调 submitQuiz，
/// 交完显示自动得分；有填空题需老师复核时一并提示。
library;

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/assignment_service.dart';
import '../../services/submission_service.dart';
import '../../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class QuizScreen extends StatefulWidget {
  final Assignment assignment;

  const QuizScreen({super.key, required this.assignment});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final _submissionService = SubmissionService();
  bool _loading = true;
  String? _error;
  List<Question> _questions = [];
  final Map<String, String> _answers = {};
  final Map<String, TextEditingController> _fillControllers = {};
  bool _submitting = false;

  Assignment get _assignment => widget.assignment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fillControllers.values) {
      c.dispose();
    }
    super.dispose();
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
      final questions =
          await AssignmentService().questionsOf(_assignment.id);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _loading = false;
        for (final q in questions) {
          if (!q.isChoice) {
            _fillControllers[q.id] = TextEditingController();
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载题目失败：$e';
      });
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  int get _answeredCount =>
      _answers.values.where((v) => v.trim().isNotEmpty).length;

  Future<void> _submit() async {
    if (_answeredCount < _questions.length) {
      final unanswered = _questions.length - _answeredCount;
      final goOn = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('还有题目没做'),
          content: Text('还有 $unanswered 道题没作答，确定现在交卷吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('继续做题'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确定交卷'),
            ),
          ],
        ),
      );
      if (goOn != true) return;
    }
    setState(() => _submitting = true);
    try {
      final submission = await _submissionService.submitQuiz(
        assignmentId: _assignment.id,
        answers: Map<String, String>.from(_answers),
      );
      final needsReview = _submissionService.needsReviewQuestions(
        _questions,
        Map<String, String>.from(_answers),
      );
      if (!mounted) return;
      final totalPoints =
          _questions.fold<int>(0, (sum, q) => sum + q.points);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('交卷成功'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '自动得分：${submission.autoScore ?? 0} 分（满分 $totalPoints 分）',
              ),
              if (submission.isLate)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '本次提交已过截止时间，记为迟交。',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              if (needsReview.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '其中 ${needsReview.length} 道填空题答案与标准答案不一致，已转给老师复核，请等老师批改结果。',
                  ),
                ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StateError catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('交卷失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_assignment.title)),
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
              : _questions.isEmpty
                  ? const EmptyView(icon: Icons.quiz_outlined, message: '这次作业还没有题目')
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('共 ${_questions.length} 道题'),
                              Text('已作答 $_answeredCount 道'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _questions.length,
                            itemBuilder: (context, index) {
                              return _questionCard(
                                  _questions[index], index);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _submitting ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                              ),
                              child:
                                  Text(_submitting ? '交卷中…' : '交卷'),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _questionCard(Question question, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                Text('${question.points} 分'),
              ],
            ),
            const SizedBox(height: 8),
            Text(question.stem, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            if (question.isChoice)
              ...question.options.map((option) {
                final selected = _answers[question.id] == option;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() => _answers[question.id] = option);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? AppTheme.primary
                              : Colors.grey.shade300,
                          width: selected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: selected
                            ? AppTheme.primary.withOpacity(0.08)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: selected
                                ? AppTheme.primary
                                : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(option)),
                        ],
                      ),
                    ),
                  ),
                );
              })
            else
              TextField(
                controller: _fillControllers[question.id],
                decoration: const InputDecoration(
                  labelText: '请输入答案',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  _answers[question.id] = value;
                },
              ),
          ],
        ),
      ),
    );
  }
}
