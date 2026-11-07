/// 我的页：真实姓名、手机号、身份、退出登录。
library;

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatelessWidget {
  final Profile? profile;

  const ProfileScreen({super.key, this.profile});

  Future<void> _signOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    await SupabaseService().signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: <Widget>[
        WeChatCard(
          child: Row(
            children: <Widget>[
              NameAvatar(name: p?.realName ?? '我', size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      p?.realName ?? '未登录',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p == null ? '' : '${p.roleLabel} · ${p.phone}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionTitle(title: '账号信息'),
        WeChatCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              _InfoRow(label: '真实姓名', value: p?.realName ?? '-'),
              const Divider(height: 1, indent: 16),
              _InfoRow(label: '手机号', value: p?.phone ?? '-'),
              const Divider(height: 1, indent: 16),
              _InfoRow(label: '身份', value: p?.roleLabel ?? '-'),
              const Divider(height: 1, indent: 16),
              _InfoRow(
                label: '登录方式',
                value: SupabaseService.isConfigured ? 'Supabase' : '演示模式',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _signOut(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: AppTheme.danger),
            ),
            child: const Text('退出登录'),
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            '作业打卡 1.0.2',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 15)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
