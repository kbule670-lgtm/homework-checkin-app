/// “肉感”动效：以后做 App 都按这份来（2026-11-08，用户看了 Ludi 的
/// 《苹果滑动的“肉感”，是怎么写出来的？》之后定的规矩）。
///
/// 视频的核心结论（WWDC 2018 第 803 场《Designing Fluid Interfaces》）：
/// 别用写死时长的缓动曲线（`transition: 0.3s ease` / `Curves.ease`），
/// 那种曲线“甩多猛，后半段都一样”，松手那一刻的速度直接断了，划起来像
/// 塑料。苹果用的是弹簧动画：不定时长，物理方程 m·x″ + c·x′ + k·x = 0，
/// 三个数就是手感——m 质量、k 刚度、c 阻尼。松手那一刻的速度直接交给
/// 弹簧当起始速度，轻轻划和猛地甩是两条不一样的路；滑到边界要弹回来一
/// 点（最早是 Bas Ording 怕人以为程序卡死才加的回弹）。
///
/// 阻尼比 ζ 是设计师主要拧的一个数（ζ = c / 2√(mk)）：
/// - ζ = 1（100%）：刚好稳稳停住，默认不晃——日常动效的起点；
/// - ζ = 0.8（80%）：有一点弹、一点挤压——如下滑关掉音乐播放页；
/// - ζ < 1：停下来会晃，像果冻，别乱用。
///
/// 落到 Flutter 上就三条：
/// 1. 所有滚动都用 BouncingScrollPhysics（包括安卓——Flutter 默认在安卓
///    用 ClampingScrollPhysics，滑到头直接顶死，最像塑料的那种）；
/// 2. 手势驱动的动效（卡片滑动、下滑关闭、抽屉）用 SpringSimulation，
///    起始速度取松手那一刻的手指速度，不写死时长；
/// 3. 到边界要回弹，别顶死。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 全平台都按 iOS 那套滚：带惯性、带边界回弹。包一层 MaterialApp 就行：
/// `MaterialApp(scrollBehavior: MeatyScrollBehavior(), ...)`.
class MeatyScrollBehavior extends ScrollBehavior {
  const MeatyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}

/// 按阻尼比造弹簧（视频里设计师主要拧的那个数）。
/// [ratio] 1.0 日常（稳稳停住）、0.8 下滑关闭那种（带一点弹）。
/// [stiffness] 弹簧多硬，100 是苹果味的起点，越大停得越干脆。
SpringDescription meatySpring({
  double ratio = 1.0,
  double stiffness = 100.0,
  double mass = 1.0,
}) {
  return SpringDescription.withDampingRatio(
    mass: mass,
    stiffness: stiffness,
    ratio: ratio,
  );
}

/// 手势驱动的弹簧模拟：松手那一刻的速度直接当起始速度，
/// 轻轻划和猛地甩走出来是两条路。用法：手势结束时拿
/// `details.velocity.pixelsPerSecond` 当 [velocity] 传进来，
/// 再把返回的 simulation 交给 AnimationController.animateWith。
SpringSimulation meatySimulation({
  required double from,
  required double to,
  required double velocity,
  double ratio = 1.0,
  double stiffness = 100.0,
}) {
  return SpringSimulation(
    meatySpring(ratio: ratio, stiffness: stiffness),
    from,
    to,
    velocity,
  );
}

/// 下滑关闭那一下（音乐播放页那种）：阻尼 0.8，有一点弹、一点挤压。
SpringSimulation dismissSimulation({
  required double from,
  required double to,
  required double velocity,
}) {
  return meatySimulation(
    from: from,
    to: to,
    velocity: velocity,
    ratio: 0.8,
  );
}
