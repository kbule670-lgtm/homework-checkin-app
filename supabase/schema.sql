-- 师生作业打卡 App（简易版）— Supabase 建表脚本
-- 执行位置：Supabase Dashboard → SQL Editor → 粘贴全文 → Run。
-- 表名、字段名按 CONTRACT.md，不得改名。执行前请先在 Supabase 项目里确认
-- 已开启 Postgres（免费版默认开启）。本文件不含任何真实 Key / 密码 / 手机号。
--
-- 注意：auth.users（登录账号）不能只用 SQL 插，必须先在 App 里注册
-- （或 Dashboard → Authentication → Add user），拿到真实 uuid 后再按
-- supabase/seed_test_data.sql 的说明替换占位 uuid。

-- ============================================================
-- 1. 扩展与枚举口径（数据库里用 text + check 约束，不用 enum 类型，
--    方便以后加取值；取值与 CONTRACT.md 的 Dart enum 一一对应）
-- ============================================================
create extension if not exists "pgcrypto";

-- ============================================================
-- 2. 九张表
-- ============================================================

-- 用户资料：id 与 auth.users.id 一一对应（注册成功后由 App 写入一行）。
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  phone text not null unique,
  real_name text not null,
  role text not null check (role in ('teacher', 'student')),
  created_at timestamptz not null default now()
);

-- 班级：老师建班，邀请码唯一。
create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  invite_code text not null unique,
  subject text,
  created_at timestamptz not null default now()
);

-- 班级成员：学生进班记录，同一学生在一个班里只有一行。
create table if not exists public.class_members (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  unique (class_id, student_id)
);

-- 作业：mode 拍照(photo)/做题(quiz)；grading_mode 100 分(score100)/优良中差(grade)。
create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes (id) on delete cascade,
  teacher_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text not null default '',
  deadline timestamptz not null,
  mode text not null check (mode in ('photo', 'quiz')),
  grading_mode text not null check (grading_mode in ('score100', 'grade')),
  created_at timestamptz not null default now()
);

-- 题目：只属于做题模式的作业；options 用 jsonb 存选项数组；answer 为空表示未设答案。
create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete cascade,
  type text not null check (type in ('choice', 'fill')),
  stem text not null,
  options jsonb not null default '[]'::jsonb,
  answer text not null default '',
  points int not null default 5 check (points >= 0),
  sort_order int not null default 0
);

-- 提交：一名学生对一份作业只有一条提交记录（批改后不允许重交，由 App 层拦截，
-- unique 约束是最后一道防线）；photo_urls 存 Storage 路径数组；answers 存题号→答案。
create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete cascade,
  student_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'submitted'
    check (status in ('submitted', 'late', 'graded')),
  photo_urls text[] not null default '{}',
  answers jsonb not null default '{}'::jsonb,
  auto_score int,
  submitted_at timestamptz not null default now(),
  is_late boolean not null default false,
  unique (assignment_id, student_id)
);

-- 批改：一份提交只有一条批改记录；score 与 grade_label 二选一（看作业 grading_mode）。
create table if not exists public.grades (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null unique references public.submissions (id) on delete cascade,
  score int check (score is null or (score >= 0 and score <= 100)),
  grade_label text check (grade_label is null or grade_label in ('优', '良', '中', '差')),
  comment text,
  graded_by uuid not null references public.profiles (id) on delete cascade,
  graded_at timestamptz not null default now()
);

-- 通知：老师发新作业时由 App 写入（简易版不接 Supabase Realtime 推送，
-- App 内轮询 + 本地通知提醒，见 NotificationService）。
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  body text not null default '',
  assignment_id uuid references public.assignments (id) on delete cascade,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 3. 常用索引
-- ============================================================
create index if not exists idx_classes_teacher on public.classes (teacher_id);
create index if not exists idx_members_class on public.class_members (class_id);
create index if not exists idx_members_student on public.class_members (student_id);
create index if not exists idx_assignments_class on public.assignments (class_id);
create index if not exists idx_questions_assignment on public.questions (assignment_id);
create index if not exists idx_submissions_assignment on public.submissions (assignment_id);
create index if not exists idx_submissions_student on public.submissions (student_id);
create index if not exists idx_notifications_user on public.notifications (user_id, created_at desc);

-- ============================================================
-- 4. 统计视图：每份作业已交 / 应交 / 迟交数（老师端统计页直接读它）
-- ============================================================
create or replace view public.completion_stats as
select
  a.id as assignment_id,
  a.class_id,
  a.title,
  (select count(*) from public.class_members m where m.class_id = a.class_id) as total_students,
  (select count(*) from public.submissions s where s.assignment_id = a.id) as submitted_count,
  (select count(*) from public.submissions s where s.assignment_id = a.id and s.is_late) as late_count,
  (select count(*) from public.submissions s where s.assignment_id = a.id and s.status = 'graded') as graded_count
from public.assignments a;

-- ============================================================
-- 5. RLS：全部开启；最小可用策略
--    原则：登录用户只能读自己相关的行；老师可写自己班的作业/批改；
--    学生只能写自己的提交；profiles 行由本人写。
-- ============================================================
alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.class_members enable row level security;
alter table public.assignments enable row level security;
alter table public.questions enable row level security;
alter table public.submissions enable row level security;
alter table public.grades enable row level security;
alter table public.notifications enable row level security;

-- profiles：本人可读写自己的行；老师可读自己班学生的行（名单要认出是谁）。
drop policy if exists "profiles_self" on public.profiles;
create policy "profiles_self" on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists "profiles_teacher_reads_students" on public.profiles;
create policy "profiles_teacher_reads_students" on public.profiles
  for select using (
    exists (
      select 1 from public.class_members m
      join public.classes c on c.id = m.class_id
      where m.student_id = profiles.id and c.teacher_id = auth.uid()
    )
  );

-- classes：老师可读写自己建的班；班里学生可读该班。
drop policy if exists "classes_teacher" on public.classes;
create policy "classes_teacher" on public.classes
  for all using (auth.uid() = teacher_id) with check (auth.uid() = teacher_id);
drop policy if exists "classes_member_read" on public.classes;
create policy "classes_member_read" on public.classes
  for select using (
    exists (select 1 from public.class_members m
            where m.class_id = classes.id and m.student_id = auth.uid())
  );

-- class_members：老师可读写自己班的成员；学生可读自己所在的班成员名单（看同学交没交），
-- 自己进班时可插入自己的一行。
drop policy if exists "members_teacher" on public.class_members;
create policy "members_teacher" on public.class_members
  for all using (
    exists (select 1 from public.classes c
            where c.id = class_members.class_id and c.teacher_id = auth.uid())
  ) with check (
    exists (select 1 from public.classes c
            where c.id = class_members.class_id and c.teacher_id = auth.uid())
  );
drop policy if exists "members_self_read" on public.class_members;
create policy "members_self_read" on public.class_members
  for select using (
    student_id = auth.uid()
    or exists (select 1 from public.class_members me
               where me.class_id = class_members.class_id
               and me.student_id = auth.uid())
  );
drop policy if exists "members_self_join" on public.class_members;
create policy "members_self_join" on public.class_members
  for insert with check (student_id = auth.uid());

-- assignments：老师可读写自己班的作业；班里学生可读。
drop policy if exists "assignments_teacher" on public.assignments;
create policy "assignments_teacher" on public.assignments
  for all using (auth.uid() = teacher_id) with check (auth.uid() = teacher_id);
drop policy if exists "assignments_member_read" on public.assignments;
create policy "assignments_member_read" on public.assignments
  for select using (
    exists (select 1 from public.class_members m
            where m.class_id = assignments.class_id and m.student_id = auth.uid())
  );

-- questions：随作业走——老师可读写自己作业的题；班里学生可读。
drop policy if exists "questions_teacher" on public.questions;
create policy "questions_teacher" on public.questions
  for all using (
    exists (select 1 from public.assignments a
            where a.id = questions.assignment_id and a.teacher_id = auth.uid())
  ) with check (
    exists (select 1 from public.assignments a
            where a.id = questions.assignment_id and a.teacher_id = auth.uid())
  );
drop policy if exists "questions_member_read" on public.questions;
create policy "questions_member_read" on public.questions
  for select using (
    exists (select 1 from public.assignments a
            join public.class_members m on m.class_id = a.class_id
            where a.id = questions.assignment_id and m.student_id = auth.uid())
  );

-- submissions：学生只能写自己的提交、读自己的提交；
-- 老师可读自己班作业的全部提交（批改用）。
drop policy if exists "submissions_student" on public.submissions;
create policy "submissions_student" on public.submissions
  for all using (auth.uid() = student_id) with check (auth.uid() = student_id);
drop policy if exists "submissions_teacher_read" on public.submissions;
create policy "submissions_teacher_read" on public.submissions
  for select using (
    exists (select 1 from public.assignments a
            where a.id = submissions.assignment_id and a.teacher_id = auth.uid())
  );
-- 老师批改后要把提交状态改成 graded：允许老师 update 自己班作业的提交状态。
drop policy if exists "submissions_teacher_mark_graded" on public.submissions;
create policy "submissions_teacher_mark_graded" on public.submissions
  for update using (
    exists (select 1 from public.assignments a
            where a.id = submissions.assignment_id and a.teacher_id = auth.uid())
  ) with check (
    exists (select 1 from public.assignments a
            where a.id = submissions.assignment_id and a.teacher_id = auth.uid())
  );

-- grades：老师可写自己班作业的批改；学生可读自己的批改。
drop policy if exists "grades_teacher" on public.grades;
create policy "grades_teacher" on public.grades
  for all using (
    exists (select 1 from public.submissions s
            join public.assignments a on a.id = s.assignment_id
            where s.id = grades.submission_id and a.teacher_id = auth.uid())
  ) with check (
    exists (select 1 from public.submissions s
            join public.assignments a on a.id = s.assignment_id
            where s.id = grades.submission_id and a.teacher_id = auth.uid())
  );
drop policy if exists "grades_student_read" on public.grades;
create policy "grades_student_read" on public.grades
  for select using (
    exists (select 1 from public.submissions s
            where s.id = grades.submission_id and s.student_id = auth.uid())
  );

-- notifications：只给本人看、本人标已读；老师发作业时按
-- notifications_teacher_insert 策略直接给本班学生插通知行（App 端写入即可，
-- 不用再走 Edge Function）；学生端同时轮询 assignments + 本地通知提醒。
drop policy if exists "notifications_self" on public.notifications;
create policy "notifications_self" on public.notifications
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 老师发作业时要给本班学生各插一条新作业通知：允许老师为自己班的学生
-- 插入通知行（仅当 assignment_id 是该老师的作业、且 user_id 是该班成员）。
-- 没有这条策略，App 端 assignment_create_screen 的插通知会直接被 RLS 拒绝。
drop policy if exists "notifications_teacher_insert" on public.notifications;
create policy "notifications_teacher_insert" on public.notifications
  for insert with check (
    exists (
      select 1 from public.assignments a
      join public.class_members m on m.class_id = a.class_id
      where a.id = notifications.assignment_id
        and a.teacher_id = auth.uid()
        and m.student_id = notifications.user_id
    )
  );

-- ============================================================
-- 6. Storage bucket：homework-photos（拍照上传用）
--    说明：bucket 本身是 storage schema 的数据，建 bucket 用下面这条
--    SQL 即可（Supabase 免费版可用）；策略：公开读、登录用户可写。
-- ============================================================
insert into storage.buckets (id, name, public)
values ('homework-photos', 'homework-photos', true)
on conflict (id) do nothing;

drop policy if exists "photos_public_read" on storage.objects;
create policy "photos_public_read" on storage.objects
  for select using (bucket_id = 'homework-photos');

drop policy if exists "photos_auth_write" on storage.objects;
create policy "photos_auth_write" on storage.objects
  for insert with check (
    bucket_id = 'homework-photos' and auth.role() = 'authenticated'
  );

drop policy if exists "photos_owner_delete" on storage.objects;
create policy "photos_owner_delete" on storage.objects
  for delete using (
    bucket_id = 'homework-photos' and auth.uid() = owner
  );
