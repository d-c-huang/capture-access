using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Reflection;
using System.Threading;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyVersion("0.8.0.0")]
[assembly: AssemblyFileVersion("0.8.0.0")]
[assembly: AssemblyProduct("Capture Access")]

namespace CaptureAccess {
    internal static class Native {
        internal delegate bool EnumProc(IntPtr hwnd, IntPtr parameter);
        [DllImport("user32.dll")] internal static extern bool EnumWindows(EnumProc callback, IntPtr parameter);
        [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] internal static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] internal static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
        [DllImport("user32.dll", SetLastError=true)] internal static extern bool GetWindowDisplayAffinity(IntPtr hwnd, out uint affinity);
        [DllImport("kernel32.dll", SetLastError=true)] internal static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
        [DllImport("kernel32.dll")] internal static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool IsWow64Process(IntPtr process, out bool wow);
        [DllImport("kernel32.dll", SetLastError=true)] internal static extern bool GetProcessTimes(IntPtr process, out long creation, out long exit, out long kernel, out long user);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] internal static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder path, ref int length);
        [DllImport("kernel32.dll")] internal static extern void GetNativeSystemInfo(out SystemInfo info);
        [StructLayout(LayoutKind.Sequential)] internal struct SystemInfo {
            internal ushort Architecture, Reserved; internal uint PageSize;
            internal IntPtr Minimum, Maximum, Mask; internal uint Count, Type, Granularity;
            internal ushort Level, Revision;
        }
        internal static ushort Architecture { get { SystemInfo info; GetNativeSystemInfo(out info); return info.Architecture; } }
        internal static bool Identity(IntPtr window, uint pid, long created) {
            uint current; if (!IsWindow(window) || GetWindowThreadProcessId(window, out current) == 0 || current != pid) return false;
            IntPtr process = OpenProcess(0x1000, false, pid);
            if (process == IntPtr.Zero) return false;
            try { long a,b,c,d; return GetProcessTimes(process, out a,out b,out c,out d) && a == created; }
            finally { CloseHandle(process); }
        }
        internal static string Affinity(uint flag) {
            if (flag == 0) return "未保护 (0)";
            if (flag == 1) return "截图留空 (1)";
            if (flag == 17) return "禁止捕获 (17)";
            return "未知标志 (" + flag + ")";
        }
    }
    internal class Target {
        internal IntPtr Window; internal uint Pid; internal long Created;
        internal bool X86, CanAccess; internal string Name, Title;
        internal string Key { get { return Window.ToInt64().ToString() + ":" + Pid + ":" + Created; } }
        internal ListViewItem Item;
    }
    internal class Watch { internal Target Target; internal uint Original; }
    internal class Reply {
        public string status { get; set; } public uint error { get; set; }
        public uint before { get; set; } public uint after { get; set; }
        public uint ack { get; set; } public uint success { get; set; }
        public uint known { get; set; } public uint changed { get; set; }
        internal bool Ok { get { return status == "ok" && success == 1 && ack == 1; } }
    }
    internal static class Engine {
        internal static Reply Apply(Target t, uint desired) {
            if (!Native.Identity(t.Window, t.Pid, t.Created)) return new Reply { status="window_changed", error=1400 };
            string helper = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "bin", t.X86 ? "CaptureHelper32.exe" : "CaptureHelper64.exe");
            if (!File.Exists(helper)) throw new FileNotFoundException("缺少组件，请完整解压压缩包。", helper);
            var start = new ProcessStartInfo(helper, String.Format(CultureInfo.InvariantCulture,
                "--set {0} {1} {2} {3}", t.Window.ToInt64(), t.Pid, t.Created, desired));
            start.UseShellExecute=false; start.CreateNoWindow=true;
            start.RedirectStandardOutput=true; start.RedirectStandardError=true;
            using (Process process=Process.Start(start)) {
                var stdout=process.StandardOutput.ReadToEndAsync();
                var stderr=process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(5000)) {
                    try { process.Kill(); process.WaitForExit(500); } catch { }
                    return new Reply { status="helper_timeout", error=1460 };
                }
                string output=stdout.GetAwaiter().GetResult().Trim();
                stderr.GetAwaiter().GetResult();
                if (output.Length==0) return new Reply { status="helper_failed", error= unchecked((uint)process.ExitCode) };
                return new JavaScriptSerializer().Deserialize<Reply>(output);
            }
        }
        internal static string Describe(Reply r) {
            if (r.Ok) return "已验证：" + Native.Affinity(r.after);
            string reason;
            switch(r.status) {
                case "window_changed": case "process_changed": reason="窗口已关闭或进程已变化，请刷新"; break;
                case "no_ack": reason="应用未执行钩子，可能不允许载入组件"; break;
                case "send_timeout": case "helper_timeout": reason="目标窗口无响应或操作超时"; break;
                case "load_library": reason="组件加载失败，请完整解压并检查架构"; break;
                case "architecture": case "arm64_unsupported": reason="目标架构不受支持"; break;
                case "hook": reason="钩子安装失败，请检查双方运行权限"; break;
                default: reason="未能修改或验证窗口保护"; break;
            }
            return reason + " [" + r.status + "; " + r.error + ": " + new Win32Exception(unchecked((int)r.error)).Message + "]";
        }
    }
    internal sealed class MainForm : Form {
        readonly ListView windows = new ListView();
        readonly TextBox filter = new TextBox(), log = new TextBox();
        readonly Label summary = new Label();
        readonly Button refresh = new Button(), apply = new Button(), restore = new Button(), elevate = new Button(), demo = new Button();
        readonly CheckBox maintain = new CheckBox();
        readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        readonly Dictionary<string, Watch> watches = new Dictionary<string, Watch>();
        List<Target> all = new List<Target>();
        bool busy, closing, canClose;
        readonly Button checkUpdate=new Button(), downloadUpdate=new Button(), settings=new Button();
        readonly Label updateSummary=new Label();
        readonly CancellationTokenSource updateLifetime=new CancellationTokenSource();
        internal readonly UpdatePreferences UpdateOptions=UpdatePreferences.LoadDefault();
        internal bool IsCheckingUpdates;
        internal UpdateRelease AvailableUpdate;
        internal string UpdateStatus="当前版本 v"+GitHubUpdates.CurrentVersion+" · 可检查 GitHub 更新";
        internal event Action UpdateStateChanged;
        SettingsForm settingsWindow;

        internal MainForm() {
            Text="Capture Access · 窗口截图保护助手";
            Font=new Font("Microsoft YaHei UI",9F); StartPosition=FormStartPosition.CenterScreen;
            AutoScaleDimensions=new SizeF(96F,96F); AutoScaleMode=AutoScaleMode.Dpi; ClientSize=new Size(1100,680); MinimumSize=new Size(980,680);
            BackColor=Color.FromArgb(246,247,249);
            var layout=new TableLayoutPanel { Dock=DockStyle.Fill,Padding=new Padding(24),ColumnCount=1,RowCount=8 };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            int[] heights={88,44,0,56,32,66,112,32};
            for(int i=0;i<heights.Length;i++) layout.RowStyles.Add(new RowStyle(i==2?SizeType.Percent:SizeType.Absolute,i==2?100:heights[i]));
            Controls.Add(layout);

            var header=new TableLayoutPanel { Dock=DockStyle.Fill,ColumnCount=2,RowCount=2,Margin=Padding.Empty };
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,112));
            header.RowStyles.Add(new RowStyle(SizeType.Absolute,43)); header.RowStyles.Add(new RowStyle(SizeType.Percent,100));
            header.Controls.Add(new Label { Text="Capture Access",Font=new Font(Font.FontFamily,23,FontStyle.Bold),Dock=DockStyle.Fill,AutoSize=true },0,0);
            header.Controls.Add(new Label { Text="选择窗口，处理截图保护。随后使用系统截图或你常用的截图工具。",ForeColor=Color.FromArgb(90,96,105),Dock=DockStyle.Fill,AutoSize=true },0,1);
            MakeButton(settings,"设置",102); settings.Anchor=AnchorStyles.Right|AnchorStyles.Top;
            header.Controls.Add(settings,1,0); layout.Controls.Add(header,0,0);

            var search=new TableLayoutPanel { Dock=DockStyle.Fill,ColumnCount=2,Margin=Padding.Empty };
            search.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,78)); search.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            search.Controls.Add(new Label { Text="筛选窗口",AutoSize=true,Anchor=AnchorStyles.Left },0,0);
            filter.Dock=DockStyle.Fill; filter.Margin=new Padding(0,5,0,8); search.Controls.Add(filter,1,0); layout.Controls.Add(search,0,1);

            var windowCard=new GroupBox { Text="应用窗口 · 按 Ctrl 可多选",Dock=DockStyle.Fill,Padding=new Padding(12),BackColor=Color.White,Margin=Padding.Empty };
            windows.Dock=DockStyle.Fill; windows.View=View.Details; windows.FullRowSelect=true; windows.HideSelection=false;
            windows.MultiSelect=true; windows.BorderStyle=BorderStyle.None; windows.GridLines=false; windows.BackColor=Color.White;
            windows.Columns.Add("应用",150); windows.Columns.Add("PID / 架构",110); windows.Columns.Add("窗口标题",380);
            windows.Columns.Add("截图保护 / 状态",340); windowCard.Controls.Add(windows); layout.Controls.Add(windowCard,0,2);
            windows.Resize+=(s,e)=>AdjustColumns();

            var buttons=new FlowLayoutPanel { Dock=DockStyle.Fill,WrapContents=false,Padding=new Padding(0,12,0,0),Margin=Padding.Empty };
            MakeButton(apply,"解除选中窗口",140); MakeButton(restore,"恢复原设置",125); MakeButton(refresh,"刷新窗口",104);
            MakeButton(demo,"打开测试窗口",140); MakeButton(elevate,"以管理员重启",140);
            apply.BackColor=Color.FromArgb(0,112,245); apply.ForeColor=Color.White; apply.FlatAppearance.BorderSize=0;
            buttons.Controls.AddRange(new Control[]{apply,restore,refresh,demo,elevate}); layout.Controls.Add(buttons,0,3);
            maintain.Text="持续解除 · 每秒检查选中窗口，正常退出时恢复原设置";
            maintain.AutoSize=true; maintain.Checked=true; maintain.Dock=DockStyle.Fill; layout.Controls.Add(maintain,0,4);

            var updates=new TableLayoutPanel { Dock=DockStyle.Fill,ColumnCount=3,RowCount=2,Margin=Padding.Empty };
            updates.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,112)); updates.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,125)); updates.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            updates.RowStyles.Add(new RowStyle(SizeType.Absolute,36)); updates.RowStyles.Add(new RowStyle(SizeType.Percent,100));
            MakeButton(checkUpdate,"检查更新",104); MakeButton(downloadUpdate,"下载更新",117); downloadUpdate.Visible=false;
            updates.Controls.Add(checkUpdate,0,0); updates.Controls.Add(downloadUpdate,1,0);
            updates.Controls.Add(new Label { Text="v"+GitHubUpdates.CurrentVersion,ForeColor=Color.DimGray,AutoSize=true,Anchor=AnchorStyles.Right },2,0);
            updateSummary.Dock=DockStyle.Fill; updateSummary.ForeColor=Color.FromArgb(90,96,105); updateSummary.AutoEllipsis=true;
            updates.Controls.Add(updateSummary,0,1); updates.SetColumnSpan(updateSummary,3); layout.Controls.Add(updates,0,5);

            var logCard=new GroupBox { Text="操作日志",Dock=DockStyle.Fill,Padding=new Padding(10),BackColor=Color.White,Margin=new Padding(0,0,0,4) };
            log.Dock=DockStyle.Fill; log.Multiline=true; log.ReadOnly=true; log.ScrollBars=ScrollBars.Vertical;
            log.BackColor=Color.White; log.BorderStyle=BorderStyle.None; logCard.Controls.Add(log); layout.Controls.Add(logCard,0,6);
            summary.Text="就绪 · 仅处理普通桌面窗口的截图保护。";
            summary.Dock=DockStyle.Fill; summary.AutoEllipsis=true; summary.Padding=new Padding(0,8,0,0); summary.ForeColor=Color.DimGray; layout.Controls.Add(summary,0,7);

            refresh.Click+=(s,e)=>RefreshWindows(); filter.TextChanged+=(s,e)=>RenderWindows();
            apply.Click+=async(s,e)=>await ApplySelected(); restore.Click+=async(s,e)=>await RestoreAll();
            elevate.Click+=async(s,e)=>await Elevate(); demo.Click+=(s,e)=>OpenDemo();
            checkUpdate.Click+=async(s,e)=>await CheckUpdates(true); downloadUpdate.Click+=(s,e)=>OpenUpdate();
            settings.Click+=(s,e)=>OpenSettings();
            timer.Interval=1000; timer.Tick+=async(s,e)=>await Maintain(); timer.Start();
            FormClosing+=OnClosing;
            FormClosed+=(s,e)=> { updateLifetime.Cancel(); updateLifetime.Dispose(); };
            Shown+=async(s,e)=> {
                RefreshWindows(); Log("仅处理明确选中的窗口；切换筛选或刷新不会自动修改其他窗口。");
                try {
                    await Task.Delay(1200,updateLifetime.Token);
                    if(!closing && !IsDisposed && UpdateOptions.ShouldCheck(DateTime.UtcNow)) await CheckUpdates(false);
                } catch(OperationCanceledException) { }
            };
            bool admin=new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
            if(admin) { Text+="（管理员）"; elevate.Enabled=false; }
            RenderUpdateState();
        }
        void AdjustColumns() {
            if(windows.Columns.Count!=4) return;
            int available=Math.Max(620,windows.ClientSize.Width-24);
            windows.Columns[0].Width=150; windows.Columns[1].Width=110;
            windows.Columns[2].Width=(available-260)*55/100;
            windows.Columns[3].Width=available-260-windows.Columns[2].Width;
        }
        void OpenSettings() {
            if(settingsWindow==null || settingsWindow.IsDisposed) settingsWindow=new SettingsForm(this);
            settingsWindow.Show(this); settingsWindow.Activate();
        }
        internal async Task CheckUpdates(bool manual) {
            if(IsCheckingUpdates || closing || IsDisposed) return;
            IsCheckingUpdates=true; AvailableUpdate=null;
            UpdateStatus="正在检查 GitHub 更新…"; RenderUpdateState();
            UpdateOptions.RecordAttempt(DateTime.UtcNow);
            if(UpdateOptions.LastSaveError!=null) Log(UpdateOptions.LastSaveError);
            try {
                var release=await GitHubUpdates.CheckAsync(updateLifetime.Token);
                if(IsDisposed) return;
                ReleaseVersion current; ReleaseVersion.TryParse(GitHubUpdates.CurrentVersion,out current);
                if(release.Version.CompareTo(current)>0) {
                    AvailableUpdate=release;
                    UpdateStatus="发现新版本 v"+release.Version+(release.HasDownload?" · 可从 GitHub 下载 Windows 更新包。":" · Windows 更新包尚未发布，可查看发布页。");
                } else {
                    UpdateStatus=release.Version.CompareTo(current)==0?"已是最新版本 · v"+GitHubUpdates.CurrentVersion:
                        "当前版本 v"+GitHubUpdates.CurrentVersion+" · GitHub 最新正式版 v"+release.Version;
                }
            } catch(OperationCanceledException) { }
            catch(Exception error) {
                if(IsDisposed) return;
                UpdateStatus=error is InvalidDataException?error.Message:"检查更新失败，请稍后重试。";
                if(manual) Log(UpdateStatus);
            } finally {
                IsCheckingUpdates=false;
                if(!IsDisposed) RenderUpdateState();
            }
        }
        internal void OpenUpdate() {
            if(AvailableUpdate==null || closing) return;
            try {
                Uri url=AvailableUpdate.DownloadURL ?? AvailableUpdate.ReleaseURL;
                Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute=true });
                UpdateStatus=AvailableUpdate.HasDownload?"已在浏览器打开 GitHub 下载。完整解压后，先退出旧版，再运行新版。":"已打开本项目的 GitHub 发布页。";
            } catch(Exception error) {
                if(!(error is Win32Exception || error is InvalidOperationException)) throw;
                UpdateStatus="未能打开浏览器，请访问项目的 GitHub Releases 页面。";
            }
            RenderUpdateState();
        }
        void RenderUpdateState() {
            checkUpdate.Enabled=!IsCheckingUpdates;
            downloadUpdate.Visible=AvailableUpdate!=null;
            downloadUpdate.Enabled=!IsCheckingUpdates;
            downloadUpdate.Text=AvailableUpdate!=null && !AvailableUpdate.HasDownload?"查看发布页":"下载更新";
            updateSummary.Text=UpdateStatus;
            if(UpdateStateChanged!=null) UpdateStateChanged();
        }
        void MakeButton(Button b,string text,int width) { b.Text=text; b.Width=width; b.Height=33; b.Margin=new Padding(0,0,8,0); b.FlatStyle=FlatStyle.Flat; b.FlatAppearance.BorderColor=Color.FromArgb(208,212,219); b.BackColor=Color.White; }
        void Log(string message) { log.AppendText(DateTime.Now.ToString("HH:mm:ss")+"  "+message+Environment.NewLine); }
        void SetBusy(bool value) {
            busy=value; refresh.Enabled=apply.Enabled=restore.Enabled=demo.Enabled=!value;
            elevate.Enabled=!value && !new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
        }
        void RefreshWindows() {
            if(busy) return;
            var found=new List<Target>(); uint self=(uint)Process.GetCurrentProcess().Id;
            Native.EnumWindows((h,p)=> {
                if(!Native.IsWindowVisible(h)) return true;
                var title=new StringBuilder(1024); Native.GetWindowText(h,title,title.Capacity);
                if(title.Length==0) return true;
                uint pid; Native.GetWindowThreadProcessId(h,out pid); if(pid==self) return true;
                var target=new Target { Window=h,Pid=pid,Title=title.ToString(),Name="PID "+pid };
                IntPtr process=Native.OpenProcess(0x1000,false,pid);
                if(process!=IntPtr.Zero) {
                    try {
                        bool wow; long a,b,c,d; var path=new StringBuilder(32768); int count=path.Capacity;
                        if(Native.QueryFullProcessImageName(process,0,path,ref count)) target.Name=Path.GetFileName(path.ToString());
                        target.CanAccess=Native.GetProcessTimes(process,out a,out b,out c,out d) && Native.IsWow64Process(process,out wow);
                        target.Created=a;
                        if(Native.IsWow64Process(process,out wow)) target.X86=Native.Architecture==0 || wow;
                    } finally { Native.CloseHandle(process); }
                }
                found.Add(target); return true;
            },IntPtr.Zero);
            all=found.OrderBy(t=>t.Name,StringComparer.CurrentCultureIgnoreCase).ThenBy(t=>t.Title).ToList(); RenderWindows();
            summary.Text=String.Format("找到 {0} 个窗口 · 已记录 {1} 个窗口的原设置",all.Count,watches.Count);
        }
        void RenderWindows() {
            var selected=new HashSet<string>(windows.SelectedItems.Cast<ListViewItem>().Select(i=>((Target)i.Tag).Key));
            windows.BeginUpdate(); windows.Items.Clear(); string query=filter.Text.Trim();
            foreach(Target t in all) {
                if(query.Length>0 && (t.Name+" "+t.Title+" "+t.Pid).IndexOf(query,StringComparison.CurrentCultureIgnoreCase)<0) continue;
                uint affinity; string state=Native.GetWindowDisplayAffinity(t.Window,out affinity)?Native.Affinity(affinity):"无法读取（不代表已保护）";
                if(!t.CanAccess) state="无法读取进程信息";
                var item=new ListViewItem(new[]{t.Name,t.Pid+" / "+(t.CanAccess?(t.X86?"x86":"x64"):"?"),t.Title,state});
                item.Tag=t; t.Item=item; item.Selected=selected.Contains(t.Key); windows.Items.Add(item);
            }
            windows.EndUpdate();
        }
        void Row(Target t,string status) {
            foreach(ListViewItem item in windows.Items) if(((Target)item.Tag).Key==t.Key) item.SubItems[3].Text=status;
        }
        async Task ApplySelected() {
            if(busy) return;
            var targets=windows.SelectedItems.Cast<ListViewItem>().Select(i=>(Target)i.Tag).ToList();
            if(targets.Count==0) { summary.Text="请先在列表中选择目标窗口。"; return; }
            if(Native.Architecture==12) { summary.Text="此版本不支持 ARM64 Windows。"; return; }
            SetBusy(true);
            try {
                foreach(Target t in targets) {
                    if(!t.CanAccess) { Log(t.Name+"：无法读取进程信息，可尝试以管理员重启工具。"); continue; }
                    Reply r=await Task.Run(()=>Engine.Apply(t,0));
                    // Save the original even when setting succeeded but verification failed.
                    if(r.ack==1 && r.known==1 && (r.Ok || r.changed==1) && !watches.ContainsKey(t.Key))
                        watches.Add(t.Key,new Watch { Target=t,Original=r.before });
                    Row(t,r.Ok?"已解除 · 当前 0":Engine.Describe(r)); Log(t.Name+" / "+t.Title+"："+Engine.Describe(r));
                }
                summary.Text="操作完成 · 已记录 "+watches.Count+" 个窗口；可截图检查，或点击“恢复原设置”。";
            } catch(Exception e) { Log("操作失败："+e.Message); summary.Text="操作未完成，请查看日志。"; }
            finally { SetBusy(false); }
        }
        async Task Maintain() {
            if(busy || closing || !maintain.Checked || watches.Count==0) return;
            SetBusy(true);
            try {
                foreach(Watch w in watches.Values.ToList()) {
                    Target t=w.Target;
                    if(!Native.Identity(t.Window,t.Pid,t.Created)) { watches.Remove(t.Key); Row(t,"窗口已关闭或变化"); continue; }
                    uint current;
                    if(Native.GetWindowDisplayAffinity(t.Window,out current) && current==0) continue;
                    Reply r=await Task.Run(()=>Engine.Apply(t,0));
                    Row(t,r.Ok?"持续解除 · 当前 0":Engine.Describe(r));
                    if(!r.Ok) { Log(t.Name+"：持续解除暂停。"+Engine.Describe(r)); maintain.Checked=false; break; }
                }
            } catch(Exception e) { Log("持续解除暂停："+e.Message); maintain.Checked=false; }
            finally { SetBusy(false); }
        }
        async Task<bool> RestoreAll() {
            if(busy) return false;
            SetBusy(true); bool ok=true;
            try {
                foreach(Watch w in watches.Values.ToList()) {
                    Target t=w.Target;
                    if(!Native.Identity(t.Window,t.Pid,t.Created)) { watches.Remove(t.Key); continue; }
                    Reply r=await Task.Run(()=>Engine.Apply(t,w.Original));
                    Row(t,r.Ok?"已恢复 · "+Native.Affinity(r.after):Engine.Describe(r));
                    Log(t.Name+"：恢复原设置。"+Engine.Describe(r));
                    if(r.Ok) watches.Remove(t.Key); else ok=false;
                }
                summary.Text=ok?"已恢复所有仍存在窗口的原设置。":"部分窗口未恢复，请查看日志；可重新尝试或重启目标应用。";
            } catch(Exception e) { ok=false; Log("恢复失败："+e.Message); }
            finally { SetBusy(false); }
            return ok;
        }
        async void OnClosing(object sender,FormClosingEventArgs e) {
            if(canClose) return;
            e.Cancel=true;
            if(closing) return;
            closing=true; timer.Stop();
            while(busy) await Task.Delay(100);
            if(watches.Count>0 && !await RestoreAll()) {
                closing=false; timer.Start();
                MessageBox.Show(this,"部分窗口未能恢复原设置。请查看日志并重试；也可以先关闭目标应用，再退出本工具。", "恢复尚未完成",MessageBoxButtons.OK,MessageBoxIcon.Information);
                return;
            }
            canClose=true; Close();
        }
        async Task Elevate() {
            if(busy) return;
            if(watches.Count>0 && !await RestoreAll()) return;
            try {
                Process.Start(new ProcessStartInfo(Application.ExecutablePath) { UseShellExecute=true,Verb="runas",WorkingDirectory=AppDomain.CurrentDomain.BaseDirectory });
                canClose=true; Close();
            } catch(Win32Exception e) { Log("管理员重启未完成："+e.Message); }
        }
        void OpenDemo() {
            try {
                string name=Native.Architecture==0?"Demo32.exe":"Demo64.exe";
                Process.Start(new ProcessStartInfo(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"tests",name)) { UseShellExecute=false });
                Log("已打开测试窗口。点击“刷新窗口”，选择 CaptureAccess test，再解除保护。");
            } catch(Exception e) { Log("无法打开测试窗口："+e.Message); }
        }
    }
    static class Program {
        [STAThread] static void Main() {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
