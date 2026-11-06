# 作业打卡 App（简易版）

老师布置作业，学生登录提交，老师批改统计。卖给老师用，一次买断 + 维护费。
Flutter 一份代码出 iOS + Android，后端用 Supabase 免费版（0 元起步）。
界面微信风，底部菜单栏 iOS 适配液态玻璃（毛玻璃 + 半透明 + 圆角悬浮）。

> 正式开工等 11 月 17 日期中考完；这份工程是 P0 简易版骨架。
> 共享契约见 `CONTRACT.md`，各组分工、表结构、方法签名以契约为准，不得自行改名、改字段、改方法签名。
> **禁止上传 GitHub，禁止联网调用付费服务。不要把真实 Key、密码、手机号写进代码。**

## 一、Supabase 怎么填

1. 打开 Supabase 官网（supabase.com），注册并新建一个免费项目；
2. 等项目建好后，在左侧菜单找到 **Settings → API**；
3. 把 **Project URL**（形如 `https://xxxx.supabase.co`）填进
   `lib/app_config.dart` 里的 `supabaseUrl`；
4. 把 **anon public** Key（Settings → API 里的 `anon public`，很长一串）
   填进 `lib/app_config.dart` 里的 `supabaseAnonKey`；
5. **只填 anon key，不要填 service_role key。** service_role 有全部权限，
   绝不能放进 App；
6. 把 `lib/app_config.dart` 里的 `isDemoMode` 改成 `false`，重新运行。

数据库表结构由 C 组写在 `supabase/schema.sql`，按契约建好 8 张表
（profiles、classes、class_members、assignments、questions、submissions、
grades、notifications）和 `homework-photos` 存储桶后，登录、建班、进班
才能走真实后端。

**没填之前也能跑：** `isDemoMode = true` 时是本地内存演示模式，
可用任意 11 位手机号注册 / 登录，点开全部界面看效果；数据只存在内存里，
退出 App 就丢，也不同步。演示模式下登录页顶部有黄色提示条。

## 二、怎么跑起来

```bash
# 1. 进工程目录
cd homework-checkin-app

# 2. 拉依赖（第一次要联网下载 pub 包，只下开源依赖，不花钱）
flutter pub get

# 3. 看静态检查（应当 0 报错；有警告先看是不是自己改动引起的）
flutter analyze

# 4. 跑起来：插手机 / 开模拟器后执行
flutter run

# 打包（需要时再用，简易版先跑通 flutter run 即可）
flutter build apk --release   # 安卓
flutter build ios --release   # iOS，需在 Xcode 里配好签名
```

环境要求：Flutter 3.22+、Dart 3.4+。安卓包名 `com.homework.checkin`，
应用名“作业打卡”，竖屏为主。

## 三、测试号格式

> 以下全是**占位格式**，不是真实账号。测试数据由 C 组写在
> `supabase/seed_test_data.sql` 和 `docs/TESTING.md`，以那两份为准。

- 老师号：11 位手机号，形如 `13800000001`（占位示例，注册时自行替换），
  注册时选“老师”，填真实姓名，密码不少于 6 位；
- 学生号：11 位手机号，形如 `13800000002`、`13800000003`（占位示例），
  注册时选“学生”，填真实姓名；
- 一台手机也能走完一圈：登老师号建班、记下 6 位邀请码 → 退出登学生号，
  输邀请码进班 → 再登老师号看成员名单；
- 想同时看两边：电脑上开安卓模拟器当第二台手机，或借一台安卓装 apk。

登录只留手机号 + 密码，不用短信验证码，不用微信 / QQ / Apple 登录
（P0 需求已定，简易版只留这一种）。

## 四、文件清单（A 组：骨架 + 登录 + 班级）

| 文件 | 作用 |
| --- | --- |
| `pubspec.yaml` | 工程配置与依赖（supabase_flutter、image_picker、file_picker、excel、archive、csv、http、intl、flutter_local_notifications、path） |
| `analysis_options.yaml` | 静态检查规则（flutter_lints） |
| `lib/main.dart` | 入口：初始化 Supabase 与本地通知，按登录态分流到登录页 / 主页 |
| `lib/app_config.dart` | Supabase 地址与 Key 占位、演示模式开关 |
| `lib/models/models.dart` | 7 个数据模型：Profile、SchoolClass、ClassMember、Assignment、Question、Submission、Grade，含 isOverdue |
| `lib/services/supabase_service.dart` | 登录、注册、退出、当前用户资料；手机号映射成 `手机号@homework.local` 走 Auth |
| `lib/services/class_service.dart` | 建班、凭邀请码进班、我的班级、成员列表；邀请码 6 位大写字母 + 数字（去 0/O/1/I） |
| `lib/services/notification_service.dart` | 本地通知初始化、新作业提醒、通知列表与已读 |
| `lib/ui/theme.dart` | 微信风主题：主色 #07C160，白底，圆角 12 卡片，#F7F7F7 背景 |
| `lib/ui/widgets/glass_tab_bar.dart` | 液态玻璃底部菜单栏 GlassTabBar（BackdropFilter blur 20 + 白色半透明 + 圆角悬浮） |
| `lib/ui/widgets/common.dart` | 通用组件：圆角卡片、空状态、加载、提示条、姓名头像 |
| `lib/ui/screens/auth_screen.dart` | 登录 / 注册页：手机号 + 密码，注册选老师 / 学生、填真实姓名 |
| `lib/ui/screens/home_screen.dart` | 主页：底部 4 tab（作业、班级、批改 / 我的提交、我的） |
| `lib/ui/screens/classes_screen.dart` | 班级列表：老师建班，学生输邀请码进班，显示班级名、邀请码、人数 |
| `lib/ui/screens/class_detail_screen.dart` | 班级详情：班级信息、成员列表（老师可见真实姓名）、本班作业入口 |
| `lib/ui/screens/profile_screen.dart` | 我的页：真实姓名、手机号、身份、退出登录 |
| `android/app/src/main/AndroidManifest.xml` | 安卓最小配置：包名 com.homework.checkin，应用名“作业打卡”，联网 / 相机 / 相册 / 通知权限 |
| `android/app/build.gradle` | 安卓构建配置：compileSdk 34，minSdk 21，targetSdk 34 |
| `ios/Runner/Info.plist` | iOS 最小配置：应用名“作业打卡”，竖屏，相机 / 相册权限说明，后台通知 |
| `README.md` | 本文件 |

B 组文件（作业 + 提交 + 批改 + 做题）与 C 组文件（导入 + 后端 + 测试）
不在本清单里，由 B / C 组各自编写；主页里作业、批改 / 我的提交两个 tab
目前是占位页，B 组文件到位后替换成正式 Screen。

## 五、已知注意事项

1. `pubspec.yaml` 里 `excel ^4.0.2` 与 `archive ^3.6.1` 已按集成结果定死：
   excel 4.x 上游依赖的是 archive 3.x，所以 archive 必须用 3.x，不能用
   4.x，否则 `flutter pub get` 会版本冲突。另补了 `http ^1.2.0`（PDF 文字
   提取调 Edge Function 要用，之前漏了）。
2. 本机没有 Flutter 环境时无法跑 `flutter analyze` / `flutter run`，
   先按契约把代码写齐，到有 Flutter 的机器上再跑上面第二节的命令验证。
