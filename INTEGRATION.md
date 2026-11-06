# 集成记录（2026-11-06，v1 本地版）

## 三组分工完成情况
- A 组（骨架+登录+班级+主界面）：20 个文件，见 README 文件清单
- B 组（作业+提交+批改+做题）：8 个文件，共 2903 行
- C 组（导入+后端+测试+自查）：11 个文件，共 1681 行
- 本地第一版共 41 个文件（含本文件、CONTRACT.md），约 7500 行

## 集成时修掉的问题（已修复，不用再改）
1. B 组 6 个 Screen 的 theme 导入写错：`'../../theme.dart'` → `'../theme.dart'`（assignment_create、assignment_detail、assignments、grading、quiz、submit_photo）。
2. `glass_tab_bar.dart` 的 theme 导入写错：`'theme.dart'` → `'../theme.dart'`。
3. `home_screen.dart` 的作业/批改两个 tab 原来是占位页，现已接上 B 组的 `AssignmentsScreen()`；第 3 tab 复用作业列表（GradingScreen 需传 assignment，不能直接当 tab 页）。
4. `class_detail_screen.dart` 的“本班作业”入口原来是占位页，现已接上 `AssignmentsScreen()`，残留占位类已删除。
5. `pubspec.yaml`：`archive ^4.0.2` → `^3.6.1`（excel 4.x 上游依赖 archive 3.x，4.x 会让 pub 解析失败）；补了 `http ^1.2.0`（PDF 文字提取调 Edge Function 要用，之前漏了）。
6. `supabase/schema.sql`：补了 `notifications_teacher_insert` 策略——原来通知表 RLS 只允许本人写自己的行，老师发作业时给学生插通知会被数据库拒绝，P0 的“新作业推送”会失败。现允许老师为自己班的学生插通知行（仅当 assignment 是该老师的、user 是该班成员）。
7. README 第五节的 excel/archive 冲突说明已按最终定稿更新。

## 自查结果
- `python3 tools/static_check.py`：95 项，95 项通过，0 失败（import 目标存在、大括号配平、CONTRACT 点名类名/方法名、无真实 URL/key/TODO 空函数）。
- 人工核对：全部导航跳转的构造参数与目标 Screen 构造器一致；Question 构造参数与 models.dart 一致；signUp/signIn 签名与 auth_screen 调用一致；全部界面文案中文；全部 Supabase 调用前判 isConfigured。
- 本机无 Flutter SDK，`flutter pub get` / `flutter analyze` / 真机编译均未跑（见下）。

## 补壳与上传准备（2026-11-06，上传批次准备）

- 壳已补上：git clone Flutter 3.22.0（shallow，~/flutter-sdk，107MB）+ `flutter create` 生成壳，只拷壳文件回工程；lib/、pubspec.yaml、android/app/build.gradle、AndroidManifest.xml、ios/Runner/Info.plist 等 41 个已有文件 md5 校验全部未变；MainActivity 包名由 `com.homework.homework_checkin` 改为 `com.homework.checkin`（与 applicationId 一致）。
- 本地找到两个真问题：① /tmp 只有 512MB，之前 curl 下 SDK 在 512MiB 处截断、Dart SDK 解压报磁盘满，根因是 SDK 放在了 /tmp，已搬到 ~/flutter-sdk（home 盘 143GB 空闲）；② tar 解压 gradle-wrapper 时想保留 uid 397546 报错，用 ~/bin/tar 包装 `--no-same-owner` 绕过。
- `flutter pub get` 本地已跑通（113 个依赖，exit 0，excel/archive 冲突修复有效）；`flutter analyze` 曾报 6 个 error（`Color.withValues` 在 Flutter 3.22 不存在），已全改成 `withOpacity`，现 0 error，只剩 11 条 info（未用辅助函数、prefer_const、supabase anonKey 废弃提示），工作流里 analyze 用 `--no-fatal-infos`。
- 工作流：`.github/workflows/flutter-build.yml`（macos-latest，Flutter 3.22：先补壳再覆盖代码 → pub get → analyze → build apk + build ios --no-codesign → 打包成 1.apk / 1.ipa 未签名 → upload-artifact）。
- 上传批次：103 个文件（41 个原有 + 工作流 1 个 + 壳 60 个 + pubspec.lock 1 个）；不含 .dart_tool/、.flutter-plugins 等生成文件；未上传 GitHub，未跑编译，无绿勾。

## 未解决 / 待下一步做的事（按优先级）
1. **原生壳不完整，GitHub 编译还不能直接跑**：android/、ios/ 目前只有 AndroidManifest、app/build.gradle、Info.plist 3 个文件，缺 settings.gradle、gradle wrapper、MainActivity、AppDelegate、Runner.xcodeproj 等 `flutter create` 生成的壳。下一步：在有 Flutter 的机器上跑 `flutter create --project-name homework_checkin --org com.homework --platforms android,ios .` 生成壳，再把本工程的 lib/pubspec/android/app/build.gradle、AndroidManifest、Info.plist 覆盖回去，然后按铁律整批一次上传 GitHub 等绿勾。
2. **未跑 `flutter analyze` / `flutter pub get`**：本机两次下载 Flutter SDK 都在 512MiB 处被截断（curl 23，疑似出口限流）；Dart SDK 下载中，拿到后至少跑 `dart format` 做语法解析。真正编译验证必须在有 Flutter 的机器（GitHub Actions 云端 Mac）上做。
3. **Supabase 项目还没建**：需要用户（或家长帮忙）在 Supabase 官网免费建项目，然后把 Project URL + anon key 填进 `lib/app_config.dart`，再在 SQL Editor 里跑 `supabase/schema.sql`，再把 `homework-photos` bucket 策略确认一遍。建项目、填 Key、跑 SQL 都不用花钱。
4. **PDF 文字提取 Edge Function 未部署**：`supabase/functions/pdf-extract/index.ts` 已写好，但要在 Supabase Dashboard 里部署，并把地址填进 `ImportService(pdfExtractUrl: ...)`（目前 `assignment_create_screen` 用的是 `const ImportService()` 空地址，PDF 导入会先报中文错，其他格式不受影响）。
5. **推送目前是“轮询 + 本地通知”占位**：真远程推送（FCM/APNs）要接 Firebase 项目 + 苹果推送证书，P0 不做；老师发作业后学生打开 App 或轮询到时弹本地通知。
6. **两个同名常量未统一**（不影响编译）：`kSupabaseNotConfiguredHint`（supabase_service）与 `kSupabaseNotConfiguredMessage`（assignment_service）是同一句话的不同名字，后续统一成一个。
7. **填空判分口径**：按“去首尾空格、全角转半角后完全一致才得分”执行（B 组方案）；P0 文档原建议未明确点头，交付时请用户确认。
8. **submissions 表没有 graded_at 列**：批改时间只记在 grades 行上，submissions 只改 status='graded'；如需 submissions 上也记时间，要改 schema.sql。
9. **测试号是占位格式**：老师 13800000001 / 学生 13800000002、13800000003，密码 Test123456——必须先在 App 里注册这三个号拿到真实 uuid，再按 `supabase/seed_test_data.sql` 的说明替换占位 uuid 才能插测试班/测试作业。

## P0 覆盖核对
- [x] 手机号+密码登录，注册选老师/学生、填真实姓名
- [x] 老师建多个班、邀请码进班，学生可加多个班
- [x] 作业两种模式：拍照上传不限张数（迟交标迟交）、App 内做题（选择自动判分）
- [x] 老师端已交/未交/迟交名单、完成率、打分+评语、学生可见分和评语、批完不能重交
- [x] 新作业推送（通知表 + 轮询本地通知；远程推送为 P1）
- [x] 导入 Excel/Word/PDF文字版/txt/CSV/JSON，扫描版 PDF 导不了
- [x] 微信风界面、iOS 液态玻璃底部栏
- [x] 0 元起步：Supabase 免费版，不租服务器，不接短信/微信/QQ 登录
- [ ] 真机编译绿勾（待 Flutter 环境 + GitHub Actions，见第 1、2 条）
