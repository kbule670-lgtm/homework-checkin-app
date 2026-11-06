/// Supabase 后端服务：登录、注册、退出、当前用户资料。
///
/// 约定（见 CONTRACT.md）：
/// - 所有调用先判 [isConfigured]，没配好时不闪退，只提示去填配置；
/// - [isDemoMode] 为 true 且没配 Supabase 时，用本地内存演示登录，
///   数据只存在内存里，退出 App 就丢；
/// - Supabase 手机号登录要接短信，简易版不用短信，所以用
///   “手机号@homework.local” 映射成邮箱走 Supabase Auth 的邮箱密码登录，
///   用户界面上只看到手机号和密码。
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart' as config;
import '../models/models.dart';

/// 没配 Supabase 时界面上显示的提示。
const String kSupabaseNotConfiguredHint =
    '请先在 lib/app_config.dart 填入 Supabase 地址和 Key';

class SupabaseService {
  static bool _initialized = false;

  /// 演示模式下的内存用户：没配 Supabase 时的登录态就存在这里。
  static Profile? _demoProfile;

  /// 演示模式下按手机号存的全部演示账号：手机号 -> 资料。
  static final Map<String, Profile> _demoProfiles = <String, Profile>{};

  /// 演示模式下的内存密码表：手机号 -> 密码（只在内存里，不落盘）。
  static final Map<String, String> _demoPasswords = <String, String>{};

  /// 初始化 Supabase。没配好时直接返回，不抛错，App 照常打开。
  static Future<void> init() async {
    if (_initialized) return;
    if (!config.isSupabaseConfigured) return;
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
    );
    _initialized = true;
  }

  /// 是否已配好 Supabase（地址和 Key 都填了）。
  static bool get isConfigured => config.isSupabaseConfigured;

  /// 是否处于演示模式：没配 Supabase 且演示开关开着。
  static bool get isDemoMode => !isConfigured && config.isDemoMode;

  /// Supabase 客户端。没配好时调用会抛中文提示，不会静默失败。
  static SupabaseClient get client {
    if (!isConfigured) {
      throw StateError(kSupabaseNotConfiguredHint);
    }
    return Supabase.instance.client;
  }

  /// 手机号映射成的内部邮箱，只在 Supabase Auth 里用，不显示给用户。
  static String emailForPhone(String phone) => '$phone@homework.local';

  /// 当前登录用户的 id。没登录返回空字符串。
  String get currentUserId {
    if (isDemoMode) return _demoProfile?.id ?? '';
    if (!isConfigured) return '';
    return Supabase.instance.client.auth.currentUser?.id ?? '';
  }

  /// 当前是否已登录（演示模式看内存，真实模式看 Auth 会话）。
  bool get isSignedIn => currentUserId.isNotEmpty;

  /// 注册：手机号 + 密码 + 真实姓名 + 身份。
  /// 注册成功后往 profiles 表插一条真实姓名和身份，老师才能认出是谁。
  Future<Profile> signUp({
    required String phone,
    required String password,
    required String realName,
    required UserRole role,
  }) async {
    if (isDemoMode) {
      if (_demoPasswords.containsKey(phone)) {
        throw StateError('该手机号已注册，请直接登录');
      }
      final profile = Profile(
        id: 'demo-${DateTime.now().millisecondsSinceEpoch}',
        phone: phone,
        realName: realName,
        role: role,
        createdAt: DateTime.now(),
      );
      _demoPasswords[phone] = password;
      _demoProfiles[phone] = profile;
      _demoProfile = profile;
      return profile;
    }
    if (!isConfigured) {
      throw StateError(kSupabaseNotConfiguredHint);
    }
    final response = await client.auth.signUp(
      email: emailForPhone(phone),
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw StateError('注册失败，请稍后重试');
    }
    final profile = Profile(
      id: user.id,
      phone: phone,
      realName: realName,
      role: role,
      createdAt: DateTime.now(),
    );
    await client.from('profiles').insert(profile.toInsert());
    return profile;
  }

  /// 登录：手机号 + 密码。
  Future<Profile> signIn({
    required String phone,
    required String password,
  }) async {
    if (isDemoMode) {
      final saved = _demoPasswords[phone];
      if (saved == null) {
        throw StateError('该手机号还没注册，请先注册');
      }
      if (saved != password) {
        throw StateError('密码不对，请重新输入');
      }
      final profile = _demoProfiles[phone];
      if (profile == null) {
        throw StateError('演示登录状态丢失，请重新注册');
      }
      _demoProfile = profile;
      return profile;
    }
    if (!isConfigured) {
      throw StateError(kSupabaseNotConfiguredHint);
    }
    final response = await client.auth.signInWithPassword(
      email: emailForPhone(phone),
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw StateError('登录失败，请检查手机号和密码');
    }
    final profile = await currentProfile();
    if (profile == null) {
      throw StateError('账号没有资料，请联系老师重新注册');
    }
    return profile;
  }

  /// 退出登录。
  Future<void> signOut() async {
    if (isDemoMode) {
      _demoProfile = null;
      return;
    }
    if (!isConfigured) return;
    await client.auth.signOut();
  }

  /// 查当前登录用户的资料（profiles 表）。没登录返回 null。
  Future<Profile?> currentProfile() async {
    if (isDemoMode) return _demoProfile;
    if (!isConfigured) return null;
    final user = client.auth.currentUser;
    if (user == null) return null;
    final row =
        await client.from('profiles').select().eq('id', user.id).maybeSingle();
    if (row == null) return null;
    return Profile.fromJson(row);
  }
}
