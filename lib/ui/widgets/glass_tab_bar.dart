/// 液态玻璃底部菜单栏：iOS 用 BackdropFilter 毛玻璃模糊 + 白色半透明 +
/// 圆角悬浮，安卓用同一套视觉（毛玻璃在安卓同样生效，只是不做系统级
/// 液态玻璃材质，视觉保持一致）。
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 底部栏的一项：标题 + 图标 + 选中时的图标。
class GlassTabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const GlassTabItem({
    required this.label,
    required this.icon,
    IconData? activeIcon,
  }) : activeIcon = activeIcon ?? icon;
}

class GlassTabBar extends StatelessWidget {
  final List<GlassTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 8 + bottomPadding * 0.5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.72),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.6),
                width: 0.5,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: <Widget>[
                  for (var i = 0; i < items.length; i++)
                    Expanded(child: _buildItem(items[i], i)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(GlassTabItem item, int index) {
    final selected = index == currentIndex;
    final color = selected ? AppTheme.primary : AppTheme.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(index),
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected ? item.activeIcon : item.icon,
                color: color,
                size: 24,
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
