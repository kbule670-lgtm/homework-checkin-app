# 师生作业打卡 App（简易版）— 共享契约

> 所有分工子代理必须遵守本契约，不得自行改名、改字段、改方法签名。
> 工程根目录：`~/workspace/homework-checkin-app/`
> 禁止上传 GitHub，禁止联网调用任何付费服务。Supabase URL / anon key 一律留空占位。

## 技术栈
- Flutter 3.x, Dart ^3.4, 一份代码出 iOS + Android
- 状态管理：不用第三方状态库，用 StatefulWidget + Service 单例 + ValueNotifier
- 后端：Supabase（免费版），表名与字段见 `supabase/schema.sql`（由 C 组编写，A/B 组按以下契约调用）
- UI：微信风，主题绿 `#07C160`，白底，圆角卡片；底部菜单栏 iOS 适配液态玻璃（毛玻璃 + 半透明 + 圆角悬浮），安卓用同一套视觉

## 数据模型（lib/models/models.dart，A 组编写，所有人 import 它）
```dart
enum UserRole { teacher, student } // 数据库存 'teacher' / 'student'
enum AssignmentMode { photo, quiz } // 数据库存 'photo' / 'quiz'
enum GradingMode { score100, grade } // 数据库存 'score100' / 'grade'
enum QuestionType { choice, fill } // 数据库存 'choice' / 'fill'
enum SubmissionStatus { submitted, late, graded } // 数据库存 'submitted' / 'late' / 'graded'

class Profile { String id; String phone; String realName; UserRole role; DateTime createdAt;
  factory Profile.fromJson(Map<String,dynamic> j); Map<String,dynamic> toInsert(); }
class SchoolClass { String id; String teacherId; String name; String inviteCode; String? subject; DateTime createdAt;
  factory SchoolClass.fromJson(Map<String,dynamic> j); }
class ClassMember { String id; String classId; String studentId; String? studentName; DateTime joinedAt;
  factory ClassMember.fromJson(Map<String,dynamic> j); }
class Assignment { String id; String classId; String teacherId; String title; String description; DateTime deadline; AssignmentMode mode; GradingMode gradingMode; DateTime createdAt;
  bool get isOverdue; factory Assignment.fromJson(Map<String,dynamic> j); }
class Question { String id; String assignmentId; QuestionType type; String stem; List<String> options; String answer; int points; int sortOrder;
  factory Question.fromJson(Map<String,dynamic> j); Map<String,dynamic> toInsert(String assignmentId); }
class Submission { String id; String assignmentId; String studentId; String? studentName; SubmissionStatus status; List<String> photoUrls; Map<String,dynamic> answers; int? autoScore; DateTime submittedAt; bool isLate;
  factory Submission.fromJson(Map<String,dynamic> j); }
class Grade { String id; String submissionId; int? score; String? gradeLabel; String? comment; String gradedBy; DateTime gradedAt;
  factory Grade.fromJson(Map<String,dynamic> j); }
```

## Supabase 表（supabase/schema.sql）
profiles(id uuid PK, phone text unique, real_name text, role text, created_at)
classes(id uuid PK, teacher_id uuid, name text, invite_code text unique, subject text, created_at)
class_members(id uuid PK, class_id uuid, student_id uuid, joined_at, unique(class_id, student_id))
assignments(id uuid PK, class_id uuid, teacher_id uuid, title text, description text, deadline timestamptz, mode text, grading_mode text, created_at)
questions(id uuid PK, assignment_id uuid, type text, stem text, options jsonb, answer text, points int, sort_order int)
submissions(id uuid PK, assignment_id uuid, student_id uuid, status text, photo_urls text[], answers jsonb, auto_score int, submitted_at timestamptz, is_late bool, unique(assignment_id, student_id))
grades(id uuid PK, submission_id uuid unique, score int, grade_label text, comment text, graded_by uuid, graded_at timestamptz)
notifications(id uuid PK, user_id uuid, title text, body text, assignment_id uuid, is_read bool, created_at)
Storage buckets: `homework-photos`（公开读、登录写）

## Service 方法签名（不得改名）
- `SupabaseService` (lib/services/supabase_service.dart): `static Future<void> init()`, `static bool get isConfigured`, `static SupabaseClient get client`, `Future<Profile> signUp({phone, password, realName, role})`, `Future<Profile> signIn({phone, password})`, `Future<void> signOut()`, `Future<Profile?> currentProfile()`, `String get currentUserId`
- `ClassService`: `Future<List<SchoolClass>> myClasses()`, `Future<SchoolClass> createClass({name, subject})`, `Future<SchoolClass> joinClass(String inviteCode)`, `Future<List<ClassMember>> membersOf(String classId)`, `String generateInviteCode()`
- `AssignmentService`: `Future<List<Assignment>> assignmentsForClass(String classId)`, `Future<List<Assignment>> myAssignments()`, `Future<Assignment> createAssignment({classId, title, description, deadline, mode, gradingMode, questions})`, `Future<List<Question>> questionsOf(String assignmentId)`
- `SubmissionService`: `Future<Submission> submitPhotos({assignmentId, photoUrls})`, `Future<Submission> submitQuiz({assignmentId, answers})`, `int autoGradeQuiz(List<Question> qs, Map<String,String> answers)`（选择题全对得分，填空去空格后完全一致才得分，对不上返回 0 并标记需老师复核——用 `needsReview` 列表返回）, `Future<List<Submission>> submissionsOf(String assignmentId)`, `Future<void> gradeSubmission({submissionId, score, gradeLabel, comment})`（批完后 submission.status='graded'，不允许重交：submit 时若已有 graded 记录直接抛 `StateError('已批改，不能重交')`）
- `ImportService`: `Future<List<Question>> parseFile(String path)`（按扩展名分发：.xlsx/.xls→Excel，.docx→Word，.pdf→走 pdf-extract Edge Function，.txt/.csv/.json→文本解析；.doc 直接抛错提示另存 .docx；扫描版 PDF 无文字层抛错提示转文字版）
- `NotificationService`: `Future<void> initLocal()`, `Future<void> checkNewAssignments()`, `Future<List<Map<String,dynamic>>> fetchNotifications()`, `Future<void> markRead(String id)`

## UI 路由（lib/main.dart，A 组）
- `/` → AuthGate：未登录 AuthScreen，已登录 HomeScreen
- HomeScreen：底部 4 个 tab：作业、班级、（老师：批改 / 学生：我的提交）、我的
- 液态玻璃 tab bar：`lib/ui/widgets/glass_tab_bar.dart` 提供 `GlassTabBar`，iOS 用 BackdropFilter 模糊 + 半透明 + 圆角悬浮，安卓同视觉降级为半透明

## 命名与风格
- 文件名小写下划线，类名大驼峰，中文界面文案，不许出现英文界面文案
- 所有 Supabase 调用必须先判 `SupabaseService.isConfigured`，未配置时显示中文提示“请先在 lib/app_config.dart 填入 Supabase 地址和 Key”，不许闪退
- 拍照上传张数无限制；截止后补交 isLate=true，status='late'；批改后 status='graded'
- 不要写任何真实 Key、密码、手机号。测试号只写进 docs/TESTING.md 的占位格式

## 各组文件分工（不许越界写别人的文件）
- A 组（骨架+登录+班级）：pubspec.yaml, analysis_options.yaml, lib/main.dart, lib/app_config.dart, lib/models/models.dart, lib/services/supabase_service.dart, lib/services/class_service.dart, lib/services/notification_service.dart, lib/ui/theme.dart, lib/ui/widgets/glass_tab_bar.dart, lib/ui/widgets/common.dart, lib/ui/screens/auth_screen.dart, lib/ui/screens/home_screen.dart, lib/ui/screens/classes_screen.dart, lib/ui/screens/class_detail_screen.dart, lib/ui/screens/profile_screen.dart, android/, ios/, README.md
- B 组（作业+提交+批改+做题）：lib/services/assignment_service.dart, lib/services/submission_service.dart, lib/ui/screens/assignments_screen.dart, lib/ui/screens/assignment_create_screen.dart, lib/ui/screens/assignment_detail_screen.dart, lib/ui/screens/submit_photo_screen.dart, lib/ui/screens/quiz_screen.dart, lib/ui/screens/grading_screen.dart
- C 组（导入+后端+测试+自查）：lib/services/import_service.dart, lib/services/parsers/question_parser.dart, lib/services/parsers/excel_parser.dart, lib/services/parsers/word_parser.dart, lib/services/parsers/pdf_text_parser.dart, supabase/schema.sql, supabase/seed_test_data.sql, supabase/functions/pdf-extract/index.ts, docs/TESTING.md, docs/IMPORT_TEMPLATES.md, tools/static_check.py
