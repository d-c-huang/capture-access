using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

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
            if (flag == 0) return "δ���� (0)";
            if (flag == 1) return "��ͼ���� (1)";
            if (flag == 17) return "��ֹ���� (17)";
            return "δ֪��־ (" + flag + ")";
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
            if (!File.Exists(helper)) throw new FileNotFoundException("ȱ���������������ѹѹ������", helper);
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
            if (r.Ok) return "����֤��" + Native.Affinity(r.after);
            string reason;
            switch(r.status) {
                case "window_changed": case "process_changed": reason="�����ѹرջ�����ѱ仯����ˢ��"; break;
                case "no_ack": reason="Ӧ��δִ�й��ӣ����ܲ������������"; break;
                case "send_timeout": case "helper_timeout": reason="Ŀ�괰������Ӧ�������ʱ"; break;
                case "load_library": reason="�������ʧ�ܣ���������ѹ�����ܹ�"; break;
                case "architecture": case "arm64_unsupported": reason="Ŀ��ܹ�����֧��"; break;
                case "hook": reason="���Ӱ�װʧ�ܣ�����˫������Ȩ��"; break;
                default: reason="δ���޸Ļ���֤���ڱ���"; break;
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
        readonly Timer timer = new Timer();
        readonly Dictionary<string, Watch> watches = new Dictionary<string, Watch>();
        List<Target> all = new List<Target>();
        bool busy, closing, canClose;

        internal MainForm() {
            Text="��ͼ�������� �� Capture Access";
            Font=new Font("Microsoft YaHei UI", 9F); StartPosition=FormStartPosition.CenterScreen;
            AutoScaleMode=AutoScaleMode.Dpi; ClientSize=new Size(1060,740); MinimumSize=new Size(940,680);
            BackColor=Color.FromArgb(245,247,250);
            var layout=new TableLayoutPanel { Dock=DockStyle.Fill, Padding=new Padding(20), ColumnCount=1, RowCount=8 };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            int[] heights={50,42,44,0,52,30,110,38};
            for(int i=0;i<heights.Length;i++) layout.RowStyles.Add(new RowStyle(i==3?SizeType.Percent:SizeType.Absolute,i==3?100:heights[i]));
            Controls.Add(layout);
            var heading=new Label { Text="ѡ�񴰿ڣ������ͼ����", Font=new Font(Font.FontFamily,19,FontStyle.Bold), AutoSize=true, Dock=DockStyle.Fill };
            layout.Controls.Add(heading,0,0);
            layout.Controls.Add(new Label { Text="������ Windows 10 / 11 ����ͨ����Ӧ�á�ѡ��һ�к������ɰ� Ctrl ��ѡ��", AutoSize=true, Dock=DockStyle.Fill },0,1);
            var search=new TableLayoutPanel { Dock=DockStyle.Fill, ColumnCount=2, Margin=Padding.Empty };
            search.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,75)); search.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            search.Controls.Add(new Label { Text="ɸѡ����", AutoSize=true, Anchor=AnchorStyles.Left },0,0);
            filter.Dock=DockStyle.Fill; filter.Margin=new Padding(0,4,0,8); search.Controls.Add(filter,1,0); layout.Controls.Add(search,0,2);
            windows.Dock=DockStyle.Fill; windows.View=View.Details; windows.FullRowSelect=true; windows.HideSelection=false;
            windows.MultiSelect=true; windows.BorderStyle=BorderStyle.FixedSingle; windows.GridLines=false;
            windows.Columns.Add("Ӧ��",145); windows.Columns.Add("PID / �ܹ�",100); windows.Columns.Add("���ڱ���",380);
            windows.Columns.Add("��ͼ���� / ״̬",340); layout.Controls.Add(windows,0,3);
            var buttons=new FlowLayoutPanel { Dock=DockStyle.Fill, WrapContents=false, Padding=new Padding(0,10,0,0) };
            MakeButton(refresh,"ˢ�´���",100); MakeButton(apply,"���ѡ�д���",140); MakeButton(restore,"�ָ�ԭ����",125);
            MakeButton(elevate,"�Թ���Ա����",140); MakeButton(demo,"�򿪲��Դ���",140);
            apply.BackColor=Color.FromArgb(25,99,218); apply.ForeColor=Color.White; apply.FlatStyle=FlatStyle.Flat;
            buttons.Controls.AddRange(new Control[]{refresh,apply,restore,elevate,demo}); layout.Controls.Add(buttons,0,4);
            maintain.Text="���������ÿ������ѡ��Ĵ��ڣ������˳�ʱ�Զ��ָ�ԭ���ã�";
            maintain.AutoSize=true; maintain.Checked=true; maintain.Dock=DockStyle.Fill; layout.Controls.Add(maintain,0,5);
            log.Dock=DockStyle.Fill; log.Multiline=true; log.ReadOnly=true; log.ScrollBars=ScrollBars.Vertical;
            log.BackColor=Color.White; layout.Controls.Add(log,0,6);
            summary.Text="���� �� ��֧�� ARM64��DRM ��Ƶ��ܾ����ع��ӵ��ܱ������̡�";
            summary.Dock=DockStyle.Fill; summary.Padding=new Padding(0,10,0,0); layout.Controls.Add(summary,0,7);
            refresh.Click+=(s,e)=>RefreshWindows(); filter.TextChanged+=(s,e)=>RenderWindows();
            apply.Click+=async(s,e)=>await ApplySelected(); restore.Click+=async(s,e)=>await RestoreAll();
            elevate.Click+=async(s,e)=>await Elevate(); demo.Click+=(s,e)=>OpenDemo();
            timer.Interval=1000; timer.Tick+=async(s,e)=>await Maintain(); timer.Start();
            FormClosing+=OnClosing;
            Shown+=(s,e)=> { RefreshWindows(); Log("��������ȷѡ�еĴ��ڣ��л�ɸѡ��ˢ�²����Զ��޸��������ڡ�"); };
            bool admin=new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
            if(admin) { Text+="������Ա��"; elevate.Enabled=false; }
        }
        void MakeButton(Button b,string text,int width) { b.Text=text; b.Width=width; b.Height=33; b.Margin=new Padding(0,0,8,0); }
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
            summary.Text=String.Format("�ҵ� {0} ������ �� �Ѽ�¼ {1} �����ڵ�ԭ����",all.Count,watches.Count);
        }
        void RenderWindows() {
            var selected=new HashSet<string>(windows.SelectedItems.Cast<ListViewItem>().Select(i=>((Target)i.Tag).Key));
            windows.BeginUpdate(); windows.Items.Clear(); string query=filter.Text.Trim();
            foreach(Target t in all) {
                if(query.Length>0 && (t.Name+" "+t.Title+" "+t.Pid).IndexOf(query,StringComparison.CurrentCultureIgnoreCase)<0) continue;
                uint affinity; string state=Native.GetWindowDisplayAffinity(t.Window,out affinity)?Native.Affinity(affinity):"�޷���ȡ���������ѱ�����";
                if(!t.CanAccess) state="�޷���ȡ������Ϣ";
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
            if(targets.Count==0) { summary.Text="�������б���ѡ��Ŀ�괰�ڡ�"; return; }
            if(Native.Architecture==12) { summary.Text="�˰汾��֧�� ARM64 Windows��"; return; }
            SetBusy(true);
            try {
                foreach(Target t in targets) {
                    if(!t.CanAccess) { Log(t.Name+"���޷���ȡ������Ϣ���ɳ����Թ���Ա�������ߡ�"); continue; }
                    Reply r=await Task.Run(()=>Engine.Apply(t,0));
                    // Save the original even when setting succeeded but verification failed.
                    if(r.ack==1 && r.known==1 && (r.Ok || r.changed==1) && !watches.ContainsKey(t.Key))
                        watches.Add(t.Key,new Watch { Target=t,Original=r.before });
                    Row(t,r.Ok?"�ѽ�� �� ��ǰ 0":Engine.Describe(r)); Log(t.Name+" / "+t.Title+"��"+Engine.Describe(r));
                }
                summary.Text="������� �� �Ѽ�¼ "+watches.Count+" �����ڣ��ɽ�ͼ��飬�������ָ�ԭ���á���";
            } catch(Exception e) { Log("����ʧ�ܣ�"+e.Message); summary.Text="����δ��ɣ���鿴��־��"; }
            finally { SetBusy(false); }
        }
        async Task Maintain() {
            if(busy || closing || !maintain.Checked || watches.Count==0) return;
            SetBusy(true);
            try {
                foreach(Watch w in watches.Values.ToList()) {
                    Target t=w.Target;
                    if(!Native.Identity(t.Window,t.Pid,t.Created)) { watches.Remove(t.Key); Row(t,"�����ѹرջ�仯"); continue; }
                    uint current;
                    if(Native.GetWindowDisplayAffinity(t.Window,out current) && current==0) continue;
                    Reply r=await Task.Run(()=>Engine.Apply(t,0));
                    Row(t,r.Ok?"������� �� ��ǰ 0":Engine.Describe(r));
                    if(!r.Ok) { Log(t.Name+"�����������ͣ��"+Engine.Describe(r)); maintain.Checked=false; break; }
                }
            } catch(Exception e) { Log("���������ͣ��"+e.Message); maintain.Checked=false; }
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
                    Row(t,r.Ok?"�ѻָ� �� "+Native.Affinity(r.after):Engine.Describe(r));
                    Log(t.Name+"���ָ�ԭ���á�"+Engine.Describe(r));
                    if(r.Ok) watches.Remove(t.Key); else ok=false;
                }
                summary.Text=ok?"�ѻָ������Դ��ڴ��ڵ�ԭ���á�":"���ִ���δ�ָ�����鿴��־�������³��Ի�����Ŀ��Ӧ�á�";
            } catch(Exception e) { ok=false; Log("�ָ�ʧ�ܣ�"+e.Message); }
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
                MessageBox.Show(this,"���ִ���δ�ָܻ�ԭ���á���鿴��־�����ԣ�Ҳ�����ȹر�Ŀ��Ӧ�ã����˳������ߡ�", "�ָ���δ���",MessageBoxButtons.OK,MessageBoxIcon.Information);
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
            } catch(Win32Exception e) { Log("����Ա����δ��ɣ�"+e.Message); }
        }
        void OpenDemo() {
            try {
                string name=Native.Architecture==0?"Demo32.exe":"Demo64.exe";
                Process.Start(new ProcessStartInfo(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"tests",name)) { UseShellExecute=false });
                Log("�Ѵ򿪲��Դ��ڡ������ˢ�´��ڡ���ѡ�� CaptureAccess test���ٽ��������");
            } catch(Exception e) { Log("�޷��򿪲��Դ��ڣ�"+e.Message); }
        }
    }
    static class Program {
        [STAThread] static void Main() {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
