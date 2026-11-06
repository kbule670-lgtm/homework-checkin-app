/// 数据模型：与 CONTRACT.md 的约定一一对应，A 组编写，所有组 import 它。
///
/// 数据库里存的都是小写英文字符串（'teacher' / 'photo' / 'score100' …），
/// 这里的枚举负责和字符串互相转换，界面上只出现中文。
library;

/// 用户身份：老师 / 学生。数据库存 'teacher' / 'student'。
enum UserRole { teacher, student }

/// 作业模式：拍照上传 / App 内做题。数据库存 'photo' / 'quiz'。
enum AssignmentMode { photo, quiz }

/// 打分方式：100 分制 / 优良中差。数据库存 'score100' / 'grade'。
enum GradingMode { score100, grade }

/// 题目类型：选择题 / 填空题。数据库存 'choice' / 'fill'。
enum QuestionType { choice, fill }

/// 提交状态：已交 / 迟交 / 已批改。数据库存 'submitted' / 'late' / 'graded'。
enum SubmissionStatus { submitted, late, graded }

UserRole _roleFromString(String value) =>
    value == 'teacher' ? UserRole.teacher : UserRole.student;

AssignmentMode _modeFromString(String value) =>
    value == 'quiz' ? AssignmentMode.quiz : AssignmentMode.photo;

GradingMode _gradingFromString(String value) =>
    value == 'grade' ? GradingMode.grade : GradingMode.score100;

QuestionType _questionTypeFromString(String value) =>
    value == 'fill' ? QuestionType.fill : QuestionType.choice;

SubmissionStatus _statusFromString(String value) {
  switch (value) {
    case 'late':
      return SubmissionStatus.late;
    case 'graded':
      return SubmissionStatus.graded;
    default:
      return SubmissionStatus.submitted;
  }
}

String _roleToString(UserRole role) =>
    role == UserRole.teacher ? 'teacher' : 'student';

String _modeToString(AssignmentMode mode) =>
    mode == AssignmentMode.quiz ? 'quiz' : 'photo';

String _gradingToString(GradingMode mode) =>
    mode == GradingMode.grade ? 'grade' : 'score100';

String _questionTypeToString(QuestionType type) =>
    type == QuestionType.fill ? 'fill' : 'choice';

String _statusToString(SubmissionStatus status) {
  switch (status) {
    case SubmissionStatus.late:
      return 'late';
    case SubmissionStatus.graded:
      return 'graded';
    case SubmissionStatus.submitted:
      return 'submitted';
  }
}

DateTime _parseDate(dynamic value, {DateTime? fallback}) {
  if (value == null) return fallback ?? DateTime.now();
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString()) ?? fallback ?? DateTime.now();
}

List<String> _stringList(dynamic value) {
  if (value == null) return <String>[];
  if (value is List) return value.map((e) => e.toString()).toList();
  return <String>[];
}

Map<String, dynamic> _stringMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return <String, dynamic>{};
}

/// 用户资料，对应 profiles 表。
class Profile {
  final String id;
  final String phone;
  final String realName;
  final UserRole role;
  final DateTime createdAt;

  const Profile({
    required this.id,
    required this.phone,
    required this.realName,
    required this.role,
    required this.createdAt,
  });

  /// 界面上显示的身份：老师 / 学生。
  String get roleLabel => role == UserRole.teacher ? '老师' : '学生';

  bool get isTeacher => role == UserRole.teacher;

  factory Profile.fromJson(Map<String, dynamic> j) {
    return Profile(
      id: (j['id'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      realName: (j['real_name'] ?? '').toString(),
      role: _roleFromString((j['role'] ?? 'student').toString()),
      createdAt: _parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toInsert() {
    return <String, dynamic>{
      'id': id,
      'phone': phone,
      'real_name': realName,
      'role': _roleToString(role),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// 班级，对应 classes 表。
class SchoolClass {
  final String id;
  final String teacherId;
  final String name;
  final String inviteCode;
  final String? subject;
  final DateTime createdAt;

  const SchoolClass({
    required this.id,
    required this.teacherId,
    required this.name,
    required this.inviteCode,
    this.subject,
    required this.createdAt,
  });

  factory SchoolClass.fromJson(Map<String, dynamic> j) {
    return SchoolClass(
      id: (j['id'] ?? '').toString(),
      teacherId: (j['teacher_id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      inviteCode: (j['invite_code'] ?? '').toString(),
      subject: j['subject']?.toString(),
      createdAt: _parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toInsert() {
    return <String, dynamic>{
      'id': id,
      'teacher_id': teacherId,
      'name': name,
      'invite_code': inviteCode,
      'subject': subject,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// 班级成员，对应 class_members 表。
class ClassMember {
  final String id;
  final String classId;
  final String studentId;
  final String? studentName;
  final DateTime joinedAt;

  const ClassMember({
    required this.id,
    required this.classId,
    required this.studentId,
    this.studentName,
    required this.joinedAt,
  });

  factory ClassMember.fromJson(Map<String, dynamic> j) {
    return ClassMember(
      id: (j['id'] ?? '').toString(),
      classId: (j['class_id'] ?? '').toString(),
      studentId: (j['student_id'] ?? '').toString(),
      studentName: j['student_name']?.toString(),
      joinedAt: _parseDate(j['joined_at']),
    );
  }
}

/// 作业，对应 assignments 表。
class Assignment {
  final String id;
  final String classId;
  final String teacherId;
  final String title;
  final String description;
  final DateTime deadline;
  final AssignmentMode mode;
  final GradingMode gradingMode;
  final DateTime createdAt;

  const Assignment({
    required this.id,
    required this.classId,
    required this.teacherId,
    required this.title,
    required this.description,
    required this.deadline,
    required this.mode,
    required this.gradingMode,
    required this.createdAt,
  });

  /// 是否已过截止时间。过了截止时间再交就是迟交。
  bool get isOverdue => DateTime.now().isAfter(deadline);

  String get modeLabel => mode == AssignmentMode.photo ? '拍照上传' : 'App 内做题';

  String get gradingLabel =>
      gradingMode == GradingMode.score100 ? '100 分制' : '优良中差';

  factory Assignment.fromJson(Map<String, dynamic> j) {
    return Assignment(
      id: (j['id'] ?? '').toString(),
      classId: (j['class_id'] ?? '').toString(),
      teacherId: (j['teacher_id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      deadline: _parseDate(j['deadline']),
      mode: _modeFromString((j['mode'] ?? 'photo').toString()),
      gradingMode:
          _gradingFromString((j['grading_mode'] ?? 'score100').toString()),
      createdAt: _parseDate(j['created_at']),
    );
  }
}

/// 题目，对应 questions 表。
class Question {
  final String id;
  final String assignmentId;
  final QuestionType type;
  final String stem;
  final List<String> options;
  final String answer;
  final int points;
  final int sortOrder;

  const Question({
    required this.id,
    required this.assignmentId,
    required this.type,
    required this.stem,
    required this.options,
    required this.answer,
    required this.points,
    required this.sortOrder,
  });

  bool get isChoice => type == QuestionType.choice;

  factory Question.fromJson(Map<String, dynamic> j) {
    return Question(
      id: (j['id'] ?? '').toString(),
      assignmentId: (j['assignment_id'] ?? '').toString(),
      type: _questionTypeFromString((j['type'] ?? 'choice').toString()),
      stem: (j['stem'] ?? '').toString(),
      options: _stringList(j['options']),
      answer: (j['answer'] ?? '').toString(),
      points: (j['points'] as num?)?.toInt() ?? 0,
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toInsert(String assignmentId) {
    return <String, dynamic>{
      'assignment_id': assignmentId,
      'type': _questionTypeToString(type),
      'stem': stem,
      'options': options,
      'answer': answer,
      'points': points,
      'sort_order': sortOrder,
    };
  }
}

/// 一次提交，对应 submissions 表。
class Submission {
  final String id;
  final String assignmentId;
  final String studentId;
  final String? studentName;
  final SubmissionStatus status;
  final List<String> photoUrls;
  final Map<String, dynamic> answers;
  final int? autoScore;
  final DateTime submittedAt;
  final bool isLate;

  const Submission({
    required this.id,
    required this.assignmentId,
    required this.studentId,
    this.studentName,
    required this.status,
    required this.photoUrls,
    required this.answers,
    this.autoScore,
    required this.submittedAt,
    required this.isLate,
  });

  String get statusLabel {
    switch (status) {
      case SubmissionStatus.submitted:
        return '已交';
      case SubmissionStatus.late:
        return '迟交';
      case SubmissionStatus.graded:
        return '已批改';
    }
  }

  bool get isGraded => status == SubmissionStatus.graded;

  factory Submission.fromJson(Map<String, dynamic> j) {
    return Submission(
      id: (j['id'] ?? '').toString(),
      assignmentId: (j['assignment_id'] ?? '').toString(),
      studentId: (j['student_id'] ?? '').toString(),
      studentName: j['student_name']?.toString(),
      status: _statusFromString((j['status'] ?? 'submitted').toString()),
      photoUrls: _stringList(j['photo_urls']),
      answers: _stringMap(j['answers']),
      autoScore: (j['auto_score'] as num?)?.toInt(),
      submittedAt: _parseDate(j['submitted_at']),
      isLate: j['is_late'] == true,
    );
  }
}

/// 一次批改，对应 grades 表。
class Grade {
  final String id;
  final String submissionId;
  final int? score;
  final String? gradeLabel;
  final String? comment;
  final String gradedBy;
  final DateTime gradedAt;

  const Grade({
    required this.id,
    required this.submissionId,
    this.score,
    this.gradeLabel,
    this.comment,
    required this.gradedBy,
    required this.gradedAt,
  });

  /// 显示用的分数或等级：有分数显示分数，否则显示优良中差。
  String get displayResult {
    if (score != null) return '$score 分';
    if (gradeLabel != null && gradeLabel!.isNotEmpty) return gradeLabel!;
    return '已批改';
  }

  factory Grade.fromJson(Map<String, dynamic> j) {
    return Grade(
      id: (j['id'] ?? '').toString(),
      submissionId: (j['submission_id'] ?? '').toString(),
      score: (j['score'] as num?)?.toInt(),
      gradeLabel: j['grade_label']?.toString(),
      comment: j['comment']?.toString(),
      gradedBy: (j['graded_by'] ?? '').toString(),
      gradedAt: _parseDate(j['graded_at']),
    );
  }
}
