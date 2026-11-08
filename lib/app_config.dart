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
///
/// 真实地址不要写进公开仓库：编译时由 GitHub Actions 从仓库 Secrets
/// 以 --dart-define=SUPABASE_URL 注入；本地没注入时保持空字符串，
/// App 按演示模式跑。
const String supabaseUrl =
    String.fromEnvironment('SUPABASE_URL', defaultValue: '');

/// Supabase anon public key（Settings -> API 里的 anon public）。
///
/// 同样由 --dart-define=SUPABASE_ANON_KEY 从仓库 Secrets 注入，不要写进
/// 公开仓库。不要填 service_role key，service_role key 有全部权限，
/// 绝不能放进 App。
const String supabaseAnonKey =
    String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

/// 演示模式开关：true 表示允许在没配 Supabase 时用本地内存演示登录
/// 和班级流程。实际是否走演示由 SupabaseService 决定：只要上面两个
/// 值注入了真实地址和 key，就走真实后端，不用改这里。
const bool isDemoMode = true;

/// 应用名（界面上显示的名字）。
const String appName = '作业打卡';

/// 界面里显示的版本号，跟 pubspec.yaml 的 version 保持一致，改版时两处一起改。
const String appVersion = '1.0.7';

/// 当前配置是否可用：地址和 Key 都填了才算配好。
bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty &&
    supabaseAnonKey.isNotEmpty &&
    supabaseUrl.startsWith('http');
