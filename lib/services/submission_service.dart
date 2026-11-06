/// 提交与批改服务：B 组。
///
/// 拍照提交、App 内做题提交、自动判分、提交列表、批改。
/// 所有方法调用 Supabase 之前都先判 [SupabaseService.isConfigured]。
library;

import '../models/models.dart';
import 'assignment_service.dart' show kSupabaseNotConfiguredMessage;
import 'supabase_service.dart';

class SubmissionService {
  String get _userId =>
      SupabaseService.client.auth.currentUser?.id ?? '';

  void _ensureConfigured() {
    if (!SupabaseService.isConfigured) {
      throw StateError(kSupabaseNotConfiguredMessage);
    }
  }

  // ---------------------------------------------------------------- 判分 --

  /// 填空答案归一化：全角转半角、去首尾空格。
  ///
  /// 全角 ASCII（U+FF01～U+FF5E）减 0xFEE0 得半角；全角空格 U+3000 转半角空格。
  static String normalizeFillAnswer(String raw) {
    final buffer = StringBuffer();
    for (final code in raw.runes) {
      if (code == 0x3000) {
        buffer.write(' ');
      } else if (code >= 0xFF01 && code <= 0xFF5E) {
        buffer.writeCharCode(code - 0xFEE0);
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString().trim();
  }

  /// 选择题的标准答案对应的选项文字。
  ///
  /// 题库里答案可能是选项文字本身，也可能是 A/B/C/D 这样的选项序号；
  /// 两种都认，避免因导入格式不同而误判。
  static String choiceCorrectText(Question q) {
    final answer = q.answer.trim();
    if (answer.length == 1) {
      final index = answer.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
      if (index >= 0 && index < q.options.length) {
        return q.options[index];
      }
    }
    return answer;
  }

  /// 选择题这道题是否答对（学生答案可能是选项文字，也可能是序号）。
  static bool isChoiceCorrect(Question q, String studentAnswer) {
    final mine = studentAnswer.trim();
    if (mine.isEmpty) return false;
    if (mine == q.answer.trim()) return true;
    return mine == choiceCorrectText(q);
  }

  /// 自动判分，返回总分。
  ///
  /// 选择题：答对得该题 points；填空题：归一化（去首尾空格、全角转半角）
  /// 后与标准答案完全一致才得分，否则 0 分、转老师复核。
  int autoGradeQuiz(
      List<Question> questions, Map<String, String> answers) {
    var total = 0;
    for (final q in questions) {
      final mine = answers[q.id] ?? '';
      if (q.isChoice) {
        if (isChoiceCorrect(q, mine)) total += q.points;
      } else {
        if (mine.isNotEmpty &&
            normalizeFillAnswer(mine) == normalizeFillAnswer(q.answer)) {
          total += q.points;
        }
      }
    }
    return total;
  }

  /// 列出需要老师复核的填空题题号（id 列表）。
  ///
  /// 填空题归一化后与标准答案对不上（含未作答）都算需复核；
  /// 选择题由机器判分，不进复核。
  List<String> needsReviewQuestions(
      List<Question> questions, Map<String, String> answers) {
    final result = <String>[];
    for (final q in questions) {
      if (q.isChoice) continue;
      final mine = answers[q.id] ?? '';
      if (normalizeFillAnswer(mine) != normalizeFillAnswer(q.answer)) {
        result.add(q.id);
      }
    }
    return result;
  }

  // ---------------------------------------------------------------- 内部查询 --

  Future<Map<String, dynamic>?> _existingSubmissionRow(
      String assignmentId, String studentId) async {
    final row = await SupabaseService.client
        .from('submissions')
        .select()
        .eq('assignment_id', assignmentId)
        .eq('student_id', studentId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<DateTime> _assignmentDeadline(String assignmentId) async {
    final row = await SupabaseService.client
        .from('assignments')
        .select('deadline')
        .eq('id', assignmentId)
        .single();
    return DateTime.parse(row['deadline'].toString());
  }

  /// 已有已批改记录时直接抛错；否则返回本次提交是否迟交。
  Future<bool> _checkResubmitAndLateness(String assignmentId) async {
    final existing =
        await _existingSubmissionRow(assignmentId, _userId);
    if (existing != null && existing['status'] == 'graded') {
      throw StateError('已批改，不能重交');
    }
    final deadline = await _assignmentDeadline(assignmentId);
    return DateTime.now().isAfter(deadline);
  }

  // ---------------------------------------------------------------- 提交 --

  /// 拍照上传提交。
  ///
  /// [photoUrls] 是已上传到 Storage homework-photos 桶的公开 URL 列表。
  /// 已批改抛错；已过截止时间则 isLate=true、status='late'，否则 'submitted'。
  Future<Submission> submitPhotos({
    required String assignmentId,
    required List<String> photoUrls,
  }) async {
    _ensureConfigured();
    if (photoUrls.isEmpty) {
      throw ArgumentError('请先选择要上传的照片');
    }
    final isLate = await _checkResubmitAndLateness(assignmentId);
    final inserted = await SupabaseService.client
        .from('submissions')
        .upsert(
          <String, dynamic>{
            'assignment_id': assignmentId,
            'student_id': _userId,
            'status': isLate ? 'late' : 'submitted',
            'photo_urls': photoUrls,
            'answers': <String, dynamic>{},
            'submitted_at': DateTime.now().toIso8601String(),
            'is_late': isLate,
          },
          onConflict: 'assignment_id,student_id',
        )
        .select()
        .single();
    return Submission.fromJson(Map<String, dynamic>.from(inserted));
  }

  /// App 内做题提交。
  ///
  /// answers 是题号到学生答案的映射，存进 answers 字段；
  /// 自动判分结果存进 auto_score；防重交与迟交逻辑与拍照提交一致。
  Future<Submission> submitQuiz({
    required String assignmentId,
    required Map<String, String> answers,
  }) async {
    _ensureConfigured();
    final isLate = await _checkResubmitAndLateness(assignmentId);
    final questionRows = await SupabaseService.client
        .from('questions')
        .select()
        .eq('assignment_id', assignmentId)
        .order('sort_order', ascending: true);
    final questions = (questionRows as List)
        .map((e) => Question.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final autoScore = autoGradeQuiz(questions, answers);
    final inserted = await SupabaseService.client
        .from('submissions')
        .upsert(
          <String, dynamic>{
            'assignment_id': assignmentId,
            'student_id': _userId,
            'status': isLate ? 'late' : 'submitted',
            'photo_urls': <String>[],
            'answers': Map<String, dynamic>.from(answers),
            'auto_score': autoScore,
            'submitted_at': DateTime.now().toIso8601String(),
            'is_late': isLate,
          },
          onConflict: 'assignment_id,student_id',
        )
        .select()
        .single();
    return Submission.fromJson(Map<String, dynamic>.from(inserted));
  }

  /// 某次作业的全部提交，按提交时间升序，并带上学生真实姓名。
  Future<List<Submission>> submissionsOf(String assignmentId) async {
    _ensureConfigured();
    final rows = await SupabaseService.client
        .from('submissions')
        .select()
        .eq('assignment_id', assignmentId)
        .order('submitted_at', ascending: true);
    final list = (rows as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (list.isEmpty) return <Submission>[];
    final studentIds =
        list.map((e) => e['student_id'].toString()).toSet().toList();
    final profileRows = await SupabaseService.client
        .from('profiles')
        .select('id, real_name')
        .inFilter('id', studentIds);
    final names = <String, String>{
      for (final r in (profileRows as List))
        (r['id'] ?? '').toString(): (r['real_name'] ?? '').toString(),
    };
    return list.map((row) {
      row['student_name'] = names[row['student_id'].toString()] ?? '';
      return Submission.fromJson(row);
    }).toList();
  }

  /// 查某次提交的批改记录（未批改返回 null）。
  Future<Grade?> gradeOfSubmission(String submissionId) async {
    _ensureConfigured();
    final row = await SupabaseService.client
        .from('grades')
        .select()
        .eq('submission_id', submissionId)
        .maybeSingle();
    if (row == null) return null;
    return Grade.fromJson(Map<String, dynamic>.from(row));
  }

  // ---------------------------------------------------------------- 批改 --

  /// 批改一次提交。
  ///
  /// 先按该作业的打分方式校验：100 分制时 score 必填 0–100；
  /// 优良中差时 gradeLabel 必填 优/良/中/差 四选一。
  /// 往 grades 插一条记录（graded_at 写在 grades 行上），再把提交状态
  /// 置为已批改（status='graded'）。
  Future<void> gradeSubmission({
    required String submissionId,
    int? score,
    String? gradeLabel,
    String? comment,
  }) async {
    _ensureConfigured();
    final submissionRow = await SupabaseService.client
        .from('submissions')
        .select('assignment_id')
        .eq('id', submissionId)
        .single();
    final assignmentRow = await SupabaseService.client
        .from('assignments')
        .select('grading_mode')
        .eq('id', submissionRow['assignment_id'].toString())
        .single();
    final gradingMode = assignmentRow['grading_mode'].toString();
    if (gradingMode == 'score100') {
      if (score == null || score < 0 || score > 100) {
        throw ArgumentError('100 分制必须填写 0 到 100 之间的分数');
      }
    } else {
      const labels = <String>{'优', '良', '中', '差'};
      if (gradeLabel == null || !labels.contains(gradeLabel)) {
        throw ArgumentError('优良中差必须选择 优、良、中、差 之一');
      }
    }
    await SupabaseService.client.from('grades').insert(<String, dynamic>{
      'submission_id': submissionId,
      'score': gradingMode == 'score100' ? score : null,
      'grade_label': gradingMode == 'score100' ? null : gradeLabel,
      'comment': (comment ?? '').trim(),
      'graded_by': _userId,
      'graded_at': DateTime.now().toIso8601String(),
    });
    await SupabaseService.client
        .from('submissions')
        .update(<String, dynamic>{'status': 'graded'})
        .eq('id', submissionId);
  }
}
