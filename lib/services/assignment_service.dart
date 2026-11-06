/// 作业服务：B 组。
///
/// 负责作业的查询、创建与题目查询。所有方法调用 Supabase 之前都先判
/// [SupabaseService.isConfigured]，未配置时抛中文错，不闪退。
library;

import '../models/models.dart';
import 'supabase_service.dart';

/// 未配置 Supabase 时统一抛出的中文提示（与 CONTRACT.md 约定一致）。
const String kSupabaseNotConfiguredMessage =
    '请先在 lib/app_config.dart 填入 Supabase 地址和 Key';

class AssignmentService {
  /// 当前登录用户 id；未登录时为空字符串。
  String get _userId =>
      SupabaseService.client.auth.currentUser?.id ?? '';

  void _ensureConfigured() {
    if (!SupabaseService.isConfigured) {
      throw StateError(kSupabaseNotConfiguredMessage);
    }
  }

  Future<Profile?> _currentProfile() async {
    final uid = _userId;
    if (uid.isEmpty) return null;
    final row = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
    if (row == null) return null;
    return Profile.fromJson(Map<String, dynamic>.from(row));
  }

  /// 某个班级的全部作业，按截止时间升序。
  Future<List<Assignment>> assignmentsForClass(String classId) async {
    _ensureConfigured();
    final rows = await SupabaseService.client
        .from('assignments')
        .select()
        .eq('class_id', classId)
        .order('deadline', ascending: true);
    return (rows as List)
        .map((e) => Assignment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 我的全部作业，按截止时间升序。
  ///
  /// 老师：我建的班的作业；学生：我加入的班的作业。
  Future<List<Assignment>> myAssignments() async {
    _ensureConfigured();
    final profile = await _currentProfile();
    if (profile == null) return <Assignment>[];

    final List<String> classIds;
    if (profile.isTeacher) {
      final rows = await SupabaseService.client
          .from('classes')
          .select('id')
          .eq('teacher_id', profile.id);
      classIds = (rows as List).map((e) => e['id'].toString()).toList();
    } else {
      final rows = await SupabaseService.client
          .from('class_members')
          .select('class_id')
          .eq('student_id', profile.id);
      classIds = (rows as List).map((e) => e['class_id'].toString()).toList();
    }
    if (classIds.isEmpty) return <Assignment>[];

    final rows = await SupabaseService.client
        .from('assignments')
        .select()
        .inFilter('class_id', classIds)
        .order('deadline', ascending: true);
    return (rows as List)
        .map((e) => Assignment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 创建作业：先插 assignments，再批量插 questions。
  ///
  /// mode 为拍照上传时 questions 可为空；mode 为 App 内做题时至少 1 题。
  Future<Assignment> createAssignment({
    required String classId,
    required String title,
    required String description,
    required DateTime deadline,
    required AssignmentMode mode,
    required GradingMode gradingMode,
    List<Question>? questions,
  }) async {
    _ensureConfigured();
    if (title.trim().isEmpty) {
      throw ArgumentError('作业标题不能为空');
    }
    final qs = questions ?? const <Question>[];
    if (mode == AssignmentMode.quiz && qs.isEmpty) {
      throw ArgumentError('App 内做题模式至少要有一道题');
    }

    final inserted = await SupabaseService.client
        .from('assignments')
        .insert(<String, dynamic>{
          'class_id': classId,
          'teacher_id': _userId,
          'title': title.trim(),
          'description': description.trim(),
          'deadline': deadline.toIso8601String(),
          'mode': mode.name,
          'grading_mode': gradingMode.name,
        })
        .select()
        .single();
    final assignment =
        Assignment.fromJson(Map<String, dynamic>.from(inserted));

    if (qs.isNotEmpty) {
      final rows = qs
          .map((q) => q.toInsert(assignment.id))
          .toList(growable: false);
      await SupabaseService.client.from('questions').insert(rows);
    }
    return assignment;
  }

  /// 某次作业的全部题目，按出题顺序升序。
  Future<List<Question>> questionsOf(String assignmentId) async {
    _ensureConfigured();
    final rows = await SupabaseService.client
        .from('questions')
        .select()
        .eq('assignment_id', assignmentId)
        .order('sort_order', ascending: true);
    return (rows as List)
        .map((e) => Question.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
