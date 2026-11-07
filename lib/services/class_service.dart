/// 班级服务：建班、凭邀请码进班、我的班级、班级成员。
///
/// 规则（见 CONTRACT.md 和 P0 需求）：
/// - 一个老师可建多个班，一个学生可加多个老师的班；
/// - 邀请码 6 位大写字母 + 数字，去掉易混淆的 0 / O / 1 / I；
/// - 重复加入同一个班要抛错，不静默覆盖；
/// - 没配 Supabase 且演示模式开着时，用内存里的演示班级走完整流程。
library;

import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'supabase_service.dart';

/// 邀请码可用字符：去掉易混淆的 0、O、1、I。
const String _inviteChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

class ClassService {
  final SupabaseService _auth = SupabaseService();

  /// 演示模式下的内存班级和成员。
  static final List<SchoolClass> _demoClasses = <SchoolClass>[];
  static final List<ClassMember> _demoMembers = <ClassMember>[];

  String _requireUserId() {
    final userId = _auth.currentUserId;
    if (userId.isEmpty) {
      throw StateError('请先登录');
    }
    return userId;
  }

  /// 生成 6 位邀请码：大写字母 + 数字，不含 0 / O / 1 / I。
  String generateInviteCode() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buffer.write(_inviteChars[random.nextInt(_inviteChars.length)]);
    }
    return buffer.toString();
  }

  /// 我的班级：老师查自己建的班，学生查自己加入的班。
  Future<List<SchoolClass>> myClasses() async {
    final userId = _requireUserId();
    if (SupabaseService.isDemoMode) {
      final profile = await _auth.currentProfile();
      if (profile != null && profile.isTeacher) {
        return _demoClasses.where((c) => c.teacherId == userId).toList();
      }
      final classIds = _demoMembers
          .where((m) => m.studentId == userId)
          .map((m) => m.classId)
          .toSet();
      return _demoClasses.where((c) => classIds.contains(c.id)).toList();
    }
    if (!SupabaseService.isConfigured) {
      throw StateError(kSupabaseNotConfiguredHint);
    }
    final profile = await _auth.currentProfile();
    final client = SupabaseService.client;
    if (profile != null && profile.isTeacher) {
      final rows = await client
          .from('classes')
          .select()
          .eq('teacher_id', userId)
          .order('created_at');
      return rows.map((r) => SchoolClass.fromJson(r)).toList();
    }
    final memberRows = await client
        .from('class_members')
        .select('class_id')
        .eq('student_id', userId);
    final classIds = memberRows
        .map((r) => (r['class_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (classIds.isEmpty) return <SchoolClass>[];
    final rows = await client
        .from('classes')
        .select()
        .inFilter('id', classIds)
        .order('created_at');
    return rows.map((r) => SchoolClass.fromJson(r)).toList();
  }

  /// 老师建班：班级名 + 科目（科目可空），自动生成邀请码。
  Future<SchoolClass> createClass({
    required String name,
    String? subject,
  }) async {
    final userId = _requireUserId();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw StateError('班级名不能为空');
    }
    if (SupabaseService.isDemoMode) {
      final schoolClass = SchoolClass(
        id: 'demo-class-${DateTime.now().millisecondsSinceEpoch}',
        teacherId: userId,
        name: trimmedName,
        inviteCode: generateInviteCode(),
        subject: subject?.trim().isEmpty == true ? null : subject?.trim(),
        createdAt: DateTime.now(),
      );
      _demoClasses.add(schoolClass);
      return schoolClass;
    }
    if (!SupabaseService.isConfigured) {
      throw StateError(kSupabaseNotConfiguredHint);
    }
    final client = SupabaseService.client;
    // 邀请码唯一，万一撞码就换一个再试，最多试 3 次。
    PostgrestException? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final row = await client
            .from('classes')
            .insert(<String, dynamic>{
              'teacher_id': userId,
              'name': trimmedName,
              'invite_code': generateInviteCode(),
              'subject':
                  subject?.trim().isEmpty == true ? null : subject?.trim(),
            })
            .select()
            .single();
        return SchoolClass.fromJson(row);
      } on PostgrestException catch (e) {
        lastError = e;
      }
    }
    throw StateError('建班失败，请稍后重试（${lastError?.message ?? ''}）');
  }

  /// 学生凭邀请码进班。邀请码不存在或已经加入过，都会抛错。
  Future<SchoolClass> joinClass(String inviteCode) async {
    final userId = _requireUserId();
    final code = inviteCode.trim().toUpperCase();
    if (code.isEmpty) {
      throw StateError('邀请码不能为空');
    }
    if (SupabaseService.isDemoMode) {
      final found = _demoClasses.where((c) => c.inviteCode == code).toList();
      if (found.isEmpty) {
        throw StateError('邀请码不存在，请核对后重试');
      }
      final schoolClass = found.first;
      final already = _demoMembers.any(
        (m) => m.classId == schoolClass.id && m.studentId == userId,
      );
      if (already) {
        throw StateError('你已经加入该班级了，不用重复加入');
      }
      _demoMembers.add(
        ClassMember(
          id: 'demo-member-${DateTime.now().millisecondsSinceEpoch}',
          classId: schoolClass.id,
          studentId: userId,
          studentName: (await _auth.currentProfile())?.realName,
          joinedAt: DateTime.now(),
        ),
      );
      return schoolClass;
    }
    if (!SupabaseService.isConfigured) {
      throw StateError(kSupabaseNotConfiguredHint);
    }
    final client = SupabaseService.client;
    final row = await client
        .from('classes')
        .select()
        .eq('invite_code', code)
        .maybeSingle();
    if (row == null) {
      throw StateError('邀请码不存在，请核对后重试');
    }
    final schoolClass = SchoolClass.fromJson(row);
    final existing = await client
        .from('class_members')
        .select('id')
        .eq('class_id', schoolClass.id)
        .eq('student_id', userId)
        .maybeSingle();
    if (existing != null) {
      throw StateError('你已经加入该班级了，不用重复加入');
    }
    await client.from('class_members').insert(<String, dynamic>{
      'class_id': schoolClass.id,
      'student_id': userId,
    });
    return schoolClass;
  }

  /// 解散班级：只删 classes 的一行；成员、作业、题目、提交、批改、通知
  /// 全是 on delete cascade，数据库会连带清掉。RLS 的 classes_teacher
  /// 策略是 for all，只有建班老师本人能删；学生调这个接口会被 RLS 拦住。
  Future<void> deleteClass(String classId) async {
    if (SupabaseService.isDemoMode) {
      _demoClasses.removeWhere((c) => c.id == classId);
      _demoMembers.removeWhere((m) => m.classId == classId);
      return;
    }
    if (!SupabaseService.isConfigured) {
      throw StateError(kSupabaseNotConfiguredHint);
    }
    await SupabaseService.client
        .from('classes')
        .delete()
        .eq('id', classId);
  }

  /// 把学生移出班级（踢人）。RLS 的 members_teacher 策略是 for all，
  /// 只有该班老师能删成员行；学生调这个接口会被 RLS 拦住。
  /// 注意：只删成员关系，不删该学生的账号，也不删他已交的作业记录
  /// （已交的作业属于班级作业历史，删班时才会随班清掉）。
  Future<void> removeMember(String classId, String studentId) async {
    if (SupabaseService.isDemoMode) {
      _demoMembers.removeWhere(
        (m) => m.classId == classId && m.studentId == studentId,
      );
      return;
    }
    if (!SupabaseService.isConfigured) {
      throw StateError(kSupabaseNotConfiguredHint);
    }
    await SupabaseService.client
        .from('class_members')
        .delete()
        .eq('class_id', classId)
        .eq('student_id', studentId);
  }

  /// 班级成员列表。老师在成员列表里能看到真实姓名。
  Future<List<ClassMember>> membersOf(String classId) async {
    if (SupabaseService.isDemoMode) {
      return _demoMembers.where((m) => m.classId == classId).toList();
    }
    if (!SupabaseService.isConfigured) {
      throw StateError(kSupabaseNotConfiguredHint);
    }
    final client = SupabaseService.client;
    final rows = await client
        .from('class_members')
        .select()
        .eq('class_id', classId)
        .order('joined_at');
    final members = rows.map((r) => ClassMember.fromJson(r)).toList();
    if (members.isEmpty) return members;
    // class_members 表里不存姓名，去 profiles 表按 id 补真实姓名。
    final studentIds = members.map((m) => m.studentId).toList();
    final profileRows = await client
        .from('profiles')
        .select('id, real_name')
        .inFilter('id', studentIds);
    final names = <String, String>{
      for (final r in profileRows)
        (r['id'] ?? '').toString(): (r['real_name'] ?? '').toString(),
    };
    return members
        .map(
          (m) => ClassMember(
            id: m.id,
            classId: m.classId,
            studentId: m.studentId,
            studentName: names[m.studentId],
            joinedAt: m.joinedAt,
          ),
        )
        .toList();
  }
}
