/// 底部菜单栏：只在 iOS 上做液态玻璃（BackdropFilter 毛玻璃模糊 +
/// 白色半透明渐变 + 玻璃边光 + 选中小玻璃片），iOS 26 以上的效果最明显；
/// 安卓不做玻璃适配，用普通白底栏（省性能、视觉也干净）。
library;

import 'dart:ui';

import 'package:flutter/foundation.dart';
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
    // 只有 iOS 做玻璃；安卓用普通白底栏。
    final useGlass = defaultTargetPlatform == TargetPlatform.iOS;
    final tabRow = SafeArea(
      top: false,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < items.length; i++)
            Expanded(child: _buildItem(items[i], i)),
        ],
      ),
    );
    if (!useGlass) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: Colors.black.withOpacity(0.06),
              width: 0.5,
            ),
          ),
        ),
        child: tabRow,
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 8 + bottomPadding * 0.5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              // 真玻璃的关键：底色要透，不能盖住背后的模糊。
              // 之前白色 0.72 太实，在浅色页面上看着就是一块白板。
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.white.withOpacity(0.58),
                  Colors.white.withOpacity(0.38),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.9),
                  width: 1,
                ),
                left: BorderSide(
                  color: Colors.white.withOpacity(0.5),
                  width: 0.5,
                ),
                right: BorderSide(
                  color: Colors.white.withOpacity(0.5),
                  width: 0.5,
                ),
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.35),
                  width: 0.5,
                ),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.5),
                  blurRadius: 1,
                  offset: const Offset(0, -0.5),
                ),
              ],
            ),
            child: tabRow,
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
              // 选中项套一个小玻璃片，像 iOS 液态玻璃 tab 栏那样浮起来。
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withOpacity(0.55)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: selected
                      ? Border.all(
                          color: Colors.white.withOpacity(0.7),
                          width: 0.5,
                        )
                      : null,
                ),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  color: color,
                  size: 24,
                ),
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
