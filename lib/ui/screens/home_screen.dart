/// 主页：底部 4 个 tab（作业、班级、批改 / 我的提交、我的）。
///
/// iOS 26+ 用真系统 UITabBar（native_liquid_glass 的 LiquidGlassTabBar，
/// 自带液态玻璃）；安卓和低版本 iOS 走自绘 GlassTabBar 兜底。
///
/// 第 3 个 tab 按身份区分：老师是“批改”，学生是“我的提交”。
/// 作业 tab 与第 3 tab 都复用 B 组的 AssignmentsScreen（无参构造）：
/// 老师在作业列表里点作业进详情再进批改页（GradingScreen 需传 assignment，
/// 不能直接当 tab 页）；学生则在同一列表里看自己的提交状态。
library;

import 'package:flutter/material.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../../models/models.dart';
import '../../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/glass_tab_bar.dart';
import 'assignments_screen.dart';
import 'classes_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final Profile? profile;

  const HomeScreen({super.key, this.profile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  Profile? _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    if (_profile == null) {
      SupabaseService().currentProfile().then((p) {
        if (mounted && p != null) setState(() => _profile = p);
      });
    }
  }

  bool get _isTeacher => _profile?.isTeacher ?? false;

  String get _title {
    switch (_currentIndex) {
      case 0:
        return '作业';
      case 1:
        return '班级';
      case 2:
        return _isTeacher ? '批改' : '我的提交';
      default:
        return '我的';
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final pages = <Widget>[
      const AssignmentsScreen(),
      ClassesScreen(profile: profile),
      const AssignmentsScreen(),
      ProfileScreen(profile: profile),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: IndexedStack(index: _currentIndex, children: pages),
      extendBody: true,
      bottomNavigationBar: NativeLiquidGlassUtils.supportsLiquidGlass
          ? LiquidGlassTabBar(
              items: <LiquidGlassTabItem>[
                const LiquidGlassTabItem(
                  label: '作业',
                  icon: NativeLiquidGlassIcon.iconData(
                    Icons.assignment_outlined,
                  ),
                  selectedIcon: NativeLiquidGlassIcon.iconData(
                    Icons.assignment,
                  ),
                ),
                const LiquidGlassTabItem(
                  label: '班级',
                  icon: NativeLiquidGlassIcon.iconData(Icons.group_outlined),
                  selectedIcon: NativeLiquidGlassIcon.iconData(Icons.group),
                ),
                LiquidGlassTabItem(
                  label: _isTeacher ? '批改' : '我的提交',
                  icon: NativeLiquidGlassIcon.iconData(
                    _isTeacher
                        ? Icons.fact_check_outlined
                        : Icons.outbox_outlined,
                  ),
                  selectedIcon: NativeLiquidGlassIcon.iconData(
                    _isTeacher ? Icons.fact_check : Icons.outbox,
                  ),
                ),
                const LiquidGlassTabItem(
                  label: '我的',
                  icon: NativeLiquidGlassIcon.iconData(Icons.person_outline),
                  selectedIcon: NativeLiquidGlassIcon.iconData(Icons.person),
                ),
              ],
              currentIndex: _currentIndex,
              onTabSelected: (index) => setState(() => _currentIndex = index),
              selectedItemColor: AppTheme.primary,
            )
          : GlassTabBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              items: <GlassTabItem>[
                const GlassTabItem(
                  label: '作业',
                  icon: Icons.assignment_outlined,
                  activeIcon: Icons.assignment,
                ),
                const GlassTabItem(
                  label: '班级',
                  icon: Icons.group_outlined,
                  activeIcon: Icons.group,
                ),
                GlassTabItem(
                  label: _isTeacher ? '批改' : '我的提交',
                  icon: _isTeacher
                      ? Icons.fact_check_outlined
                      : Icons.outbox_outlined,
                  activeIcon: _isTeacher ? Icons.fact_check : Icons.outbox,
                ),
                const GlassTabItem(
                  label: '我的',
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                ),
              ],
            ),
    );
  }
}

