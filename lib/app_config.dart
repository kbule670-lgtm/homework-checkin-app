/// 应用配置：Supabase 连接信息集中放在这里。
///
/// 填写方法（不要把真实 Key 提交到公开仓库）：
/// 1. 打开 Supabase 官网，新建一个免费项目；
/// 2. 在项目后台左侧找到 Settings -> API；
/// 3. 把 Project URL 填进 [supabaseUrl]，把 anon public Key 填进
///    [supabaseAnonKey]（只填 anon key，不要填 service_role key，
///    service_role key 有全部权限，绝不能放进 App）；
/// 4. 把 [isDemoMode] 改成 false，重新运行 App。
///
/// 没填之前 App 也能打开：[isDemoMode] 为 true 时用本地内存演示登录，
/// 可以点开全部界面看效果，但数据只存在内存里、退出就丢，也不同步。
library;

/// Supabase 项目地址，例如 https://xxxx.supabase.co
/// 没配好之前保持空字符串。
const String supabaseUrl = '';

/// Supabase anon public key（Settings -> API 里的 anon public）。
/// 没配好之前保持空字符串。不要填 service_role key。
const String supabaseAnonKey = '';

/// 演示模式：true 时没配 Supabase 也能用本地内存演示登录和班级流程；
/// 配好 Supabase 后改成 false，走真实后端。
const bool isDemoMode = true;

/// 应用名（界面上显示的名字）。
const String appName = '作业打卡';

/// 当前配置是否可用：地址和 Key 都填了才算配好。
bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty &&
    supabaseAnonKey.isNotEmpty &&
    supabaseUrl.startsWith('http');
