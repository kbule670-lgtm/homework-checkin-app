-- 修复 RLS 策略死循环（infinite recursion, 错误码 42P17）
--
-- 问题：schema.sql 里部分策略在判断权限时直接去查同一张（或互相引用
-- 的）表，例如 class_members 的 members_self_read 策略里又查
-- class_members、classes 的策略查 class_members 而 class_members 的
-- 策略又查 classes，数据库查权限时来回套娃，直接报
-- infinite recursion detected in policy for relation "class_members"，
-- 作业页一点开就加载失败（500）。
--
-- 修法（Supabase 官方推荐做法）：权限判断改走 SECURITY DEFINER 的
-- 辅助函数。函数内部查表时绕过 RLS，不会再触发策略，也就不会递归。
-- 策略本身的权限口径不变：能看什么、能改什么，和原来一模一样。
--
-- 执行位置：Supabase Dashboard → SQL Editor → 粘贴全文 → Run。
-- 跑完不用重编、不用重装 App，手机上点“重试”就能加载。
-- 同时请把 supabase/schema.sql 里第 5 节换成同一套写法，免得以后
-- 新建项目又踩同一个坑。

-- ============================================================
-- 1. 辅助函数：全部 SECURITY DEFINER（函数内查表绕过 RLS）
-- ============================================================

-- 是不是这个班的老师
create or replace function public.is_class_teacher(p_class_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.classes c
    where c.id = p_class_id and c.teacher_id = auth.uid()
  );
$$;

-- 是不是这个班的学生
create or replace function public.is_class_member(p_class_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.class_members m
    where m.class_id = p_class_id and m.student_id = auth.uid()
  );
$$;

-- 是不是这份作业的老师
create or replace function public.is_assignment_teacher(p_assignment_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.assignments a
    where a.id = p_assignment_id and a.teacher_id = auth.uid()
  );
$$;

-- 是不是这份作业所在班的学生
create or replace function public.is_assignment_member(p_assignment_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.assignments a
    join public.class_members m on m.class_id = a.class_id
    where a.id = p_assignment_id and m.student_id = auth.uid()
  );
$$;

-- 是不是我班上的学生（老师看学生名单用）
create or replace function public.is_my_student(p_student_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.class_members m
    join public.classes c on c.id = m.class_id
    where m.student_id = p_student_id and c.teacher_id = auth.uid()
  );
$$;

-- 是不是这份提交所属作业的老师（批改用）
create or replace function public.is_submission_assignment_teacher(p_submission_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.submissions s
    join public.assignments a on a.id = s.assignment_id
    where s.id = p_submission_id and a.teacher_id = auth.uid()
  );
$$;

-- 是不是这份提交的主人（学生看自己的批改用）
create or replace function public.is_submission_owner(p_submission_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.submissions s
    where s.id = p_submission_id and s.student_id = auth.uid()
  );
$$;

-- 老师给这份作业的这个学生发通知是否合法
create or replace function public.can_notify(p_assignment_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.assignments a
    join public.class_members m on m.class_id = a.class_id
    where a.id = p_assignment_id
      and a.teacher_id = auth.uid()
      and m.student_id = p_user_id
  );
$$;

-- ============================================================
-- 2. 重写策略：口径不变，只把“直接查表”换成“调辅助函数”
-- ============================================================

-- profiles：老师可读自己班学生的行
drop policy if exists "profiles_teacher_reads_students" on public.profiles;
create policy "profiles_teacher_reads_students" on public.profiles
  for select using (public.is_my_student(id));

-- classes：班里学生可读该班
drop policy if exists "classes_member_read" on public.classes;
create policy "classes_member_read" on public.classes
  for select using (public.is_class_member(id));

-- class_members：老师可读写自己班的成员；学生可读自己所在的班成员名单
drop policy if exists "members_teacher" on public.class_members;
create policy "members_teacher" on public.class_members
  for all using (public.is_class_teacher(class_id))
  with check (public.is_class_teacher(class_id));
drop policy if exists "members_self_read" on public.class_members;
create policy "members_self_read" on public.class_members
  for select using (
    student_id = auth.uid() or public.is_class_member(class_id)
  );

-- assignments：班里学生可读
drop policy if exists "assignments_member_read" on public.assignments;
create policy "assignments_member_read" on public.assignments
  for select using (public.is_class_member(class_id));

-- questions：老师可读写自己作业的题；班里学生可读
drop policy if exists "questions_teacher" on public.questions;
create policy "questions_teacher" on public.questions
  for all using (public.is_assignment_teacher(assignment_id))
  with check (public.is_assignment_teacher(assignment_id));
drop policy if exists "questions_member_read" on public.questions;
create policy "questions_member_read" on public.questions
  for select using (public.is_assignment_member(assignment_id));

-- submissions：老师可读自己班作业的全部提交；老师批改后可改状态为 graded
drop policy if exists "submissions_teacher_read" on public.submissions;
create policy "submissions_teacher_read" on public.submissions
  for select using (public.is_assignment_teacher(assignment_id));
drop policy if exists "submissions_teacher_mark_graded" on public.submissions;
create policy "submissions_teacher_mark_graded" on public.submissions
  for update using (public.is_assignment_teacher(assignment_id))
  with check (public.is_assignment_teacher(assignment_id));

-- grades：老师可写自己班作业的批改；学生可读自己的批改
drop policy if exists "grades_teacher" on public.grades;
create policy "grades_teacher" on public.grades
  for all using (public.is_submission_assignment_teacher(submission_id))
  with check (public.is_submission_assignment_teacher(submission_id));
drop policy if exists "grades_student_read" on public.grades;
create policy "grades_student_read" on public.grades
  for select using (public.is_submission_owner(submission_id));

-- notifications：老师发作业时给本班学生插通知行
drop policy if exists "notifications_teacher_insert" on public.notifications;
create policy "notifications_teacher_insert" on public.notifications
  for insert with check (
    public.can_notify(assignment_id, user_id)
  );
