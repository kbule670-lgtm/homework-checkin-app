/// 新建作业页（老师专用）：B 组。
///
/// 标题、说明、截止时间选择器、模式二选一（拍照上传 / App 内做题）、
/// 打分方式二选一（100 分制 / 优良中差）。做题模式可点“导入题目”
/// 调 ImportService.parseFile，也可手动加一题。发布后往 notifications 表
/// 给该班所有学生各插一条新作业通知。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../services/assignment_service.dart';
import '../../services/import_service.dart';
import '../../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AssignmentCreateScreen extends StatefulWidget {
  /// 已选好的班级（从班级详情页进来时传）；为空时页内选班级。
  final String? classId;
  final String? className;

  const AssignmentCreateScreen({super.key, this.classId, this.className});

  @override
  State<AssignmentCreateScreen> createState() =>
      _AssignmentCreateScreenState();
}

class _AssignmentCreateScreenState extends State<AssignmentCreateScreen> {
  final _assignmentService = AssignmentService();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _deadline;
  AssignmentMode _mode = AssignmentMode.photo;
  GradingMode _gradingMode = GradingMode.score100;
  List<Question> _questions = [];
  List<SchoolClass> _classes = [];
  String? _selectedClassId;
  bool _loadingClasses = true;
  bool _publishing = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _selectedClassId = widget.classId;
    _loadClasses();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    if (!SupabaseService.isConfigured) {
      setState(() => _loadingClasses = false);
      return;
    }
    try {
      final uid = SupabaseService.client.auth.currentUser?.id ?? '';
      final rows = await SupabaseService.client
          .from('classes')
          .select()
          .eq('teacher_id', uid)
          .order('created_at', ascending: true);
      if (!mounted) return;
      setState(() {
        _classes = (rows as List)
            .map((e) => SchoolClass.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _loadingClasses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingClasses = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: '选择截止日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _deadline ?? now.add(const Duration(hours: 1))),
      helpText: '选择截止时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (time == null) return;
    setState(() {
      _deadline = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  /// 导入题目：支持 Excel / Word(.docx) / PDF 文字版 / txt / CSV / JSON。
  Future<void> _importQuestions() async {
    if (!SupabaseService.isConfigured) {
      _showMessage(kSupabaseNotConfiguredMessage);
      return;
    }
    setState(() => _importing = true);
    try {
      // withData: true：iOS 上从 iCloud 选文件时经常拿不到本地路径，
      // 只给 bytes；这时先把 bytes 写进临时文件再解析，扩展名保持原样。
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      var path = picked.path;
      if ((path == null || path.isEmpty) && picked.bytes != null) {
        final ext = (picked.extension ?? '').isEmpty
            ? 'txt'
            : picked.extension!;
        path =
            '${Directory.systemTemp.path}/import_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await File(path).writeAsBytes(picked.bytes!);
      }
      if (path == null || path.isEmpty) {
        _showMessage('无法读取该文件，请换一个文件再试');
        return;
      }
      final parsed = await const ImportService().parseFile(path);
      if (!mounted) return;
      setState(() {
        // 导入的题接在已有题目后面，并按顺序重新编号，
        // 保证入库顺序与显示一致。
        _questions = [
          ..._questions,
          ...parsed,
        ];
      });
      _showMessage('已导入 ${parsed.length} 道题');
    } catch (e) {
      _showMessage('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 手动加一题：题干 + 选项 + 答案。
  Future<void> _addQuestionManually() async {
    final stemController = TextEditingController();
    final answerController = TextEditingController();
    final pointsController = TextEditingController(text: '5');
    final optionControllers =
        List.generate(4, (_) => TextEditingController());
    var type = QuestionType.choice;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('手动加一题'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<QuestionType>(
                      segments: const [
                        ButtonSegment(
                          value: QuestionType.choice,
                          label: Text('选择题'),
                        ),
                        ButtonSegment(
                          value: QuestionType.fill,
                          label: Text('填空题'),
                        ),
                      ],
                      selected: {type},
                      onSelectionChanged: (selected) {
                        setDialogState(() => type = selected.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stemController,
                      decoration: const InputDecoration(
                        labelText: '题干',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    if (type == QuestionType.choice) ...[
                      const SizedBox(height: 12),
                      for (var i = 0; i < optionControllers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: optionControllers[i],
                            decoration: InputDecoration(
                              labelText:
                                  '选项 ${String.fromCharCode('A'.codeUnitAt(0) + i)}',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      const Text(
                        '答案填选项内容，或填 A、B、C、D 这样的序号',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: answerController,
                      decoration: const InputDecoration(
                        labelText: '答案',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pointsController,
                      decoration: const InputDecoration(
                        labelText: '分值',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('加入'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) return;
    final stem = stemController.text.trim();
    final answer = answerController.text.trim();
    if (stem.isEmpty || answer.isEmpty) {
      _showMessage('题干和答案不能为空');
      return;
    }
    final options = type == QuestionType.choice
        ? optionControllers
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList()
        : <String>[];
    if (type == QuestionType.choice && options.length < 2) {
      _showMessage('选择题至少要有两个选项');
      return;
    }
    final points = int.tryParse(pointsController.text.trim()) ?? 5;
    setState(() {
      _questions = [
        ..._questions,
        Question(
          id: '',
          assignmentId: '',
          type: type,
          stem: stem,
          options: options,
          answer: answer,
          points: points,
          sortOrder: _questions.length,
        ),
      ];
    });
  }

  Future<void> _publish() async {
    if (!SupabaseService.isConfigured) {
      _showMessage(kSupabaseNotConfiguredMessage);
      return;
    }
    final classId = _selectedClassId;
    if (classId == null || classId.isEmpty) {
      _showMessage('请先选择班级');
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      _showMessage('请填写作业标题');
      return;
    }
    if (_deadline == null) {
      _showMessage('请选择截止时间');
      return;
    }
    if (_mode == AssignmentMode.quiz && _questions.isEmpty) {
      _showMessage('App 内做题模式至少要有一道题，请导入或手动添加');
      return;
    }
    setState(() => _publishing = true);
    try {
      final questions = _mode == AssignmentMode.quiz
          ? [
              for (var i = 0; i < _questions.length; i++)
                Question(
                  id: _questions[i].id,
                  assignmentId: _questions[i].assignmentId,
                  type: _questions[i].type,
                  stem: _questions[i].stem,
                  options: _questions[i].options,
                  answer: _questions[i].answer,
                  points: _questions[i].points,
                  sortOrder: i,
                ),
            ]
          : <Question>[];
      final assignment = await _assignmentService.createAssignment(
        classId: classId,
        title: _titleController.text,
        description: _descriptionController.text,
        deadline: _deadline!,
        mode: _mode,
        gradingMode: _gradingMode,
        questions: questions,
      );
      await _notifyStudents(classId, assignment);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _showMessage('发布失败：$e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  /// 往 notifications 表给该班所有学生各插一条新作业通知。
  Future<void> _notifyStudents(
      String classId, Assignment assignment) async {
    final memberRows = await SupabaseService.client
        .from('class_members')
        .select('student_id')
        .eq('class_id', classId);
    final studentIds = (memberRows as List)
        .map((e) => e['student_id'].toString())
        .toSet()
        .toList();
    if (studentIds.isEmpty) return;
    final deadlineText =
        DateFormat('yyyy年MM月dd日 HH:mm').format(assignment.deadline);
    await SupabaseService.client.from('notifications').insert(
          studentIds
              .map((studentId) => <String, dynamic>{
                    'user_id': studentId,
                    'title': '新作业：${assignment.title}',
                    'body':
                        '老师布置了新作业《${assignment.title}》，截止时间 $deadlineText，请按时提交。',
                    'assignment_id': assignment.id,
                    'is_read': false,
                  })
              .toList(),
        );
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseService.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('新建作业')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              kSupabaseNotConfiguredMessage,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('新建作业')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.classId == null)
              DropdownButtonFormField<String>(
                value: _selectedClassId,
                decoration: const InputDecoration(
                  labelText: '班级',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in _classes)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (value) {
                  setState(() => _selectedClassId = value);
                },
              )
            else
              Text('班级：${widget.className ?? ''}',
                  style: const TextStyle(fontSize: 16)),
            if (_loadingClasses && widget.classId == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LoadingView(),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '作业标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '作业说明',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('截止时间'),
              subtitle: Text(
                _deadline == null
                    ? '未选择'
                    : DateFormat('yyyy年MM月dd日 HH:mm').format(_deadline!),
              ),
              trailing: FilledButton.tonal(
                onPressed: _pickDeadline,
                child: const Text('选择时间'),
              ),
            ),
            const SizedBox(height: 8),
            const Text('作业模式', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<AssignmentMode>(
              segments: const [
                ButtonSegment(
                  value: AssignmentMode.photo,
                  label: Text('拍照上传'),
                ),
                ButtonSegment(
                  value: AssignmentMode.quiz,
                  label: Text('App 内做题'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selected) {
                setState(() => _mode = selected.first);
              },
            ),
            const SizedBox(height: 16),
            const Text('打分方式', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<GradingMode>(
              segments: const [
                ButtonSegment(
                  value: GradingMode.score100,
                  label: Text('100 分制'),
                ),
                ButtonSegment(
                  value: GradingMode.grade,
                  label: Text('优良中差'),
                ),
              ],
              selected: {_gradingMode},
              onSelectionChanged: (selected) {
                setState(() => _gradingMode = selected.first);
              },
            ),
            if (_mode == AssignmentMode.quiz) ...[
              const SizedBox(height: 24),
              // 标题和两个按钮不要挤在同一行：窄屏上会溢出到屏幕外，
              // 按钮直接看不见、点不着。标题一行，按钮另起一行平分宽度。
              Text(
                '题目（${_questions.length} 道）',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _importing ? null : _importQuestions,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text(_importing ? '导入中…' : '导入题目'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addQuestionManually,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('手动加一题'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '导入支持 Excel、Word、PDF 文字版、txt、CSV、JSON；老版 .doc 请另存为 .docx，扫描版 PDF 请转文字版。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              if (_questions.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('还没有题目，请导入或手动添加。'),
                  ),
                )
              else
                for (var i = 0; i < _questions.length; i++)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text('第 ${i + 1} 题（${_questions[i].points} 分）'),
                      subtitle: Text(
                        _questions[i].stem,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除这道题',
                        onPressed: () {
                          setState(() {
                            _questions = List.of(_questions)..removeAt(i);
                          });
                        },
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _publishing ? null : _publish,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_publishing ? '发布中…' : '发布作业'),
            ),
          ],
        ),
      ),
    );
  }
}
