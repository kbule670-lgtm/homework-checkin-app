/// 登录 / 注册页：手机号 + 密码，注册时选老师 / 学生、填真实姓名。
///
/// 校验：手机号 11 位、密码不少于 6 位，注册时真实姓名必填。
/// 没配 Supabase 时：演示模式开着可直接体验；演示模式关着则提示去填配置。
library;

import 'package:flutter/material.dart';

import '../../app_config.dart' as config;
import '../../models/models.dart';
import '../../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  UserRole _role = UserRole.student;
  bool _obscurePassword = true;
  bool _busy = false;

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _service = SupabaseService();

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _showDemoHint => !SupabaseService.isConfigured && config.isDemoMode;

  String? _validate() {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      return '手机号不对，请输入 11 位手机号';
    }
    if (password.length < 6) {
      return '密码至少 6 位';
    }
    if (!_isLogin && _nameController.text.trim().isEmpty) {
      return '请填写真实姓名，老师要靠名字认出你';
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      showAppSnackBar(context, error, isError: true);
      return;
    }
    if (!SupabaseService.isConfigured && !config.isDemoMode) {
      showAppSnackBar(
        context,
        kSupabaseNotConfiguredHint,
        isError: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final phone = _phoneController.text.trim();
      final password = _passwordController.text;
      final Profile profile;
      if (_isLogin) {
        profile = await _service.signIn(phone: phone, password: password);
      } else {
        profile = await _service.signUp(
          phone: phone,
          password: password,
          realName: _nameController.text.trim(),
          role: _role,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HomeScreen(profile: profile),
        ),
      );
    } on StateError catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, '网络有点问题，请稍后重试', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 56, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '作业打卡',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isLogin ? '老师布置作业，学生打卡提交' : '注册一个账号，开始用作业打卡',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              if (_showDemoHint)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '演示模式：还没填 Supabase 配置，现在是本地演示，数据只存在内存里。正式使用请按 README 填好 lib/app_config.dart。',
                    style: TextStyle(fontSize: 13, color: Color(0xFF8A6D00)),
                  ),
                ),
              if (_showDemoHint) const SizedBox(height: 16),
              if (!_isLogin) ...<Widget>[
                const Text('你是', style: TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _RoleChoice(
                        label: '老师',
                        selected: _role == UserRole.teacher,
                        onTap: () => setState(() => _role = UserRole.teacher),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleChoice(
                        label: '学生',
                        selected: _role == UserRole.student,
                        onTap: () => setState(() => _role = UserRole.student),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '真实姓名',
                    hintText: '请填写真实姓名',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                maxLength: 11,
                decoration: const InputDecoration(
                  labelText: '手机号',
                  hintText: '请输入 11 位手机号',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '至少 6 位',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(_isLogin ? '登录' : '注册'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed:
                    _busy ? null : () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin ? '没有账号？去注册' : '已有账号？去登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: selected ? AppTheme.primary : AppTheme.textPrimary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
