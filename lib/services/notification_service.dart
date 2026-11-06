/// 通知服务：本地通知初始化、新作业提醒、通知列表与已读。
///
/// 流程：老师发新作业时往 notifications 表插一条记录（B 组作业服务负责），
/// 这里定期查自己未读的通知，弹一条本地通知提醒学生。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'supabase_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'homework_channel',
    '作业通知',
    channelDescription: '新作业与批改提醒',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const NotificationDetails _details =
      NotificationDetails(android: _androidDetails);

  bool _initialized = false;

  /// 初始化本地通知。安卓用应用图标，iOS 首次会弹授权（这里先不强制索权，
  /// 只在收到通知时按系统规则展示；如需前台横幅可在设置里打开通知权限）。
  Future<void> initLocal() async {
    if (_initialized) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// 查 notifications 表里自己的未读通知，逐条弹本地通知。
  /// 没配 Supabase 或演示模式下直接返回，不做任何事。
  Future<void> checkNewAssignments() async {
    if (SupabaseService.isDemoMode || !SupabaseService.isConfigured) return;
    await initLocal();
    final unread = await fetchNotifications();
    final fresh = unread.where((n) => n['is_read'] != true).toList();
    var index = 0;
    for (final item in fresh) {
      final title = (item['title'] ?? '新作业').toString();
      final body = (item['body'] ?? '').toString();
      await _plugin.show(index, title, body, _details);
      index++;
    }
  }

  /// 拉取自己的通知列表，按时间倒序。没配 Supabase 时返回空列表。
  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    if (SupabaseService.isDemoMode || !SupabaseService.isConfigured) {
      return <Map<String, dynamic>>[];
    }
    final userId = SupabaseService().currentUserId;
    if (userId.isEmpty) return <Map<String, dynamic>>[];
    final rows = await SupabaseService.client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// 把一条通知标为已读。没配 Supabase 时直接返回。
  Future<void> markRead(String id) async {
    if (SupabaseService.isDemoMode || !SupabaseService.isConfigured) return;
    await SupabaseService.client
        .from('notifications')
        .update(<String, dynamic>{'is_read': true}).eq('id', id);
  }

  /// 直接弹一条本地通知（供作业、批改流程调用）。
  Future<void> showLocal({
    required int id,
    required String title,
    required String body,
  }) async {
    await initLocal();
    await _plugin.show(id, title, body, _details);
  }
}
