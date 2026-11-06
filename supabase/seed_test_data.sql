-- 师生作业打卡 App（简易版）— 测试数据种子脚本
-- 执行顺序：① 先执行 supabase/schema.sql；② 在 App 里注册下面三个测试号，
-- 拿到真实 uuid；③ 把下面的占位 uuid 替换成真实 uuid，再执行本文件。
--
-- ============================================================
-- 重要：auth.users 不能只用 SQL 插！
-- ============================================================
-- 登录账号存在 auth.users 表里，密码是加密哈希，SQL 插不进去。
-- 正确做法：在 App 注册页（或 Supabase Dashboard → Authentication → Add user）
-- 注册下面三个号，注册成功后到 Dashboard → Authentication → Users 里复制
-- 每个账号的 User UID，再替换下面 @teacher_id / @student1_id / @student2_id。
-- 不要把这三个号当成“已经注册好的账号”——没注册之前，它们只是占位写法。
--
-- 测试号清单（占位格式，仅用于测试，密码统一 Test123456）：
--   老师：13800000001 / Test123456（姓名：测试老师）
--   学生1：13800000002 / Test123456（姓名：测试学生甲）
--   学生2：13800000003 / Test123456（姓名：测试学生乙）
-- 注意：手机号只是登录用的账号名，不会真的发短信；密码不要用于正式账号。

-- ============ 第 1 步：把占位 uuid 替换成真实 uuid ============
-- 在 Supabase SQL Editor 里先执行下面三行 SET（替换成真实值），
-- 再执行后面的插入语句。也可以直接把下面的 'xxxxxxxx-...' 换掉。
-- set app.teacher_id = '真实老师 uuid';
-- set app.student1_id = '真实学生甲 uuid';
-- set app.student2_id = '真实学生乙 uuid';

-- 下面是未替换前的占位写法（直接执行会因外键失败，属于预期行为，
-- 目的是提醒你先注册、再替换）：
--   老师占位 uuid：11111111-1111-4111-8111-111111111111
--   学生甲占位 uuid：22222222-2222-4222-8222-222222222222
--   学生乙占位 uuid：33333333-3333-4333-8333-333333333333

-- ============ 第 2 步：插测试班、测试作业、测试题目 ============
begin;

-- profiles 行：注册成功后 App 会自动写一行；这里是补写口径——
-- 如果 App 注册时已写过 profiles，下面三条会因主键冲突失败，
-- 改成 on conflict (id) do update 即可（已写好，直接执行）。
insert into public.profiles (id, phone, real_name, role) values
  ('11111111-1111-4111-8111-111111111111', '13800000001', '测试老师', 'teacher'),
  ('22222222-2222-4222-8222-222222222222', '13800000002', '测试学生甲', 'student'),
  ('33333333-3333-4333-8333-333333333333', '13800000003', '测试学生乙', 'student')
on conflict (id) do update
  set phone = excluded.phone,
      real_name = excluded.real_name,
      role = excluded.role;

-- 测试班（邀请码 TEST01，固定写死，方便测试时输入）。
insert into public.classes (id, teacher_id, name, invite_code, subject) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   '11111111-1111-4111-8111-111111111111',
   '测试班（高二 15 班）', 'TEST01', '英语')
on conflict (invite_code) do nothing;

-- 两个学生进班。
insert into public.class_members (class_id, student_id) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-2222-4222-8222-222222222222'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '33333333-3333-4333-8333-333333333333')
on conflict (class_id, student_id) do nothing;

-- 测试作业 1：做题模式（截止时间写执行当天之后 7 天，见下）。
insert into public.assignments
  (id, class_id, teacher_id, title, description, deadline, mode, grading_mode) values
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   '11111111-1111-4111-8111-111111111111',
   '测试作业：英语选择填空',
   '测试用作业，包含 2 道选择、1 道填空。',
   now() + interval '7 days',
   'quiz', 'score100')
on conflict (id) do nothing;

-- 测试作业 2：拍照模式。
insert into public.assignments
  (id, class_id, teacher_id, title, description, deadline, mode, grading_mode) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   '11111111-1111-4111-8111-111111111111',
   '测试作业：课文背诵拍照',
   '把背诵的课文页拍照上传，张数不限。',
   now() + interval '7 days',
   'photo', 'grade')
on conflict (id) do nothing;

-- 测试题目（挂在作业 1 下面，与 docs/IMPORT_TEMPLATES.md 的例题一致）。
insert into public.questions
  (assignment_id, type, stem, options, answer, points, sort_order) values
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'choice',
   '下列哪个单词的意思是“环境”？',
   '["environment", "envelope", "episode", "equipment"]'::jsonb, 'A', 5, 0),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'choice',
   'The Olympic Games ______ every four years.',
   '["hold", "are held", "held", "holding"]'::jsonb, 'B', 5, 1),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'fill',
   '请写出 protect 的名词形式：______',
   '[]'::jsonb, 'protection', 5, 2);

commit;

-- ============ 第 3 步：清空测试数据（测坏了重来用） ============
-- 只删测试班 TEST01 及其名下的一切（作业、题目、提交、批改、成员），
-- 不碰其他班的数据。执行前确认 invite_code 是 TEST01。
--
-- begin;
-- delete from public.classes where invite_code = 'TEST01';
-- -- 级联删除会自动清掉该班的作业、题目、提交、批改与成员记录
-- -- （外键均已设 on delete cascade）。
-- -- profiles 与 auth.users 里的测试账号不会被删掉，
-- -- 想连账号一起清掉，去 Dashboard → Authentication → Users 里删。
-- commit;
--
-- 只清某一份测试作业的提交（保留作业本身）：
-- delete from public.submissions
--  where assignment_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
