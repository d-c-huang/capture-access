using System;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace CaptureAccess {
    internal sealed class SettingsForm : Form {
        readonly MainForm owner;
        readonly CheckBox automaticUpdates=new CheckBox(), launchAtLogin=new CheckBox();
        readonly Label startupExplanation=new Label(), updateStatus=new Label(), preferenceStatus=new Label();
        readonly Button check=new Button(), download=new Button();
        bool loadingStartup;

        internal SettingsForm(MainForm main) {
            owner=main;
            Text="Capture Access · 设置"; Font=new Font("Microsoft YaHei UI",9F);
            StartPosition=FormStartPosition.CenterParent; AutoScaleDimensions=new SizeF(96F,96F); AutoScaleMode=AutoScaleMode.Dpi;
            ClientSize=new Size(680,500); MinimumSize=new Size(620,520); MaximizeBox=false;
            BackColor=Color.FromArgb(246,247,249);
            var layout=new TableLayoutPanel { Dock=DockStyle.Fill,Padding=new Padding(24),ColumnCount=1,RowCount=5 };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute,48));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute,112));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute,38));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute,38));
            Controls.Add(layout);
            layout.Controls.Add(new Label { Text="设置",Dock=DockStyle.Fill,Font=new Font(Font.FontFamily,19,FontStyle.Bold) },0,0);

            var startupCard=new GroupBox { Text="启动",Dock=DockStyle.Fill,Padding=new Padding(16,22,16,10),BackColor=Color.White,Margin=new Padding(0,0,0,12) };
            var startupLayout=new TableLayoutPanel { Dock=DockStyle.Fill,ColumnCount=1,RowCount=2 };
            startupLayout.RowStyles.Add(new RowStyle(SizeType.Absolute,30)); startupLayout.RowStyles.Add(new RowStyle(SizeType.Percent,100));
            launchAtLogin.Text="登录 Windows 时启动 Capture Access"; launchAtLogin.AutoSize=true; launchAtLogin.Dock=DockStyle.Fill;
            startupExplanation.ForeColor=Color.DimGray; startupExplanation.Dock=DockStyle.Fill; startupExplanation.AutoSize=true;
            startupLayout.Controls.Add(launchAtLogin,0,0); startupLayout.Controls.Add(startupExplanation,0,1); startupCard.Controls.Add(startupLayout); layout.Controls.Add(startupCard,0,1);

            var updateCard=new GroupBox { Text="软件更新",Dock=DockStyle.Fill,Padding=new Padding(16,20,16,12),BackColor=Color.White,Margin=Padding.Empty };
            var updateLayout=new TableLayoutPanel { Dock=DockStyle.Fill,ColumnCount=1,RowCount=4 };
            updateLayout.RowStyles.Add(new RowStyle(SizeType.Absolute,30)); updateLayout.RowStyles.Add(new RowStyle(SizeType.Absolute,42));
            updateLayout.RowStyles.Add(new RowStyle(SizeType.Absolute,40)); updateLayout.RowStyles.Add(new RowStyle(SizeType.Percent,100));
            automaticUpdates.Text="启动时自动检查更新"; automaticUpdates.AutoSize=true; automaticUpdates.Checked=owner.UpdateOptions.AutomaticChecks;
            updateLayout.Controls.Add(automaticUpdates,0,0);
            updateLayout.Controls.Add(new Label { Text="每 24 小时最多自动检查一次。仅向本项目的 GitHub 查询版本，不发送窗口列表、日志或截图。",Dock=DockStyle.Fill,ForeColor=Color.DimGray },0,1);
            var commands=new FlowLayoutPanel { Dock=DockStyle.Fill,WrapContents=false,Margin=Padding.Empty };
            StyleButton(check,"检查更新",105); StyleButton(download,"下载更新",115);
            commands.Controls.Add(check); commands.Controls.Add(download); updateLayout.Controls.Add(commands,0,2);
            updateStatus.Dock=DockStyle.Fill; updateStatus.ForeColor=Color.FromArgb(90,96,105); updateStatus.AutoSize=true;
            updateLayout.Controls.Add(updateStatus,0,3); updateCard.Controls.Add(updateLayout); layout.Controls.Add(updateCard,0,2);
            preferenceStatus.Dock=DockStyle.Fill; preferenceStatus.ForeColor=Color.Firebrick; preferenceStatus.Padding=new Padding(0,8,0,0); layout.Controls.Add(preferenceStatus,0,3);
            var footer=new TableLayoutPanel { Dock=DockStyle.Fill,ColumnCount=2,Margin=Padding.Empty };
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,92));
            var repository=new LinkLabel { Text="Capture Access v"+GitHubUpdates.CurrentVersion+" · GitHub 项目",AutoSize=true,Anchor=AnchorStyles.Left };
            repository.LinkClicked+=(s,e)=>OpenRepository(); footer.Controls.Add(repository,0,0);
            var done=new Button(); StyleButton(done,"完成",86); done.Anchor=AnchorStyles.Right;
            done.Click+=(s,e)=>Close(); footer.Controls.Add(done,1,0); layout.Controls.Add(footer,0,4); AcceptButton=done; CancelButton=done;

            automaticUpdates.CheckedChanged+=(s,e)=> {
                owner.UpdateOptions.AutomaticChecks=automaticUpdates.Checked; owner.UpdateOptions.Save();
                preferenceStatus.Text=owner.UpdateOptions.LastSaveError ?? "";
            };
            launchAtLogin.CheckedChanged+=(s,e)=>SetStartup();
            check.Click+=async(s,e)=>await owner.CheckUpdates(true);
            download.Click+=(s,e)=>owner.OpenUpdate();
            owner.UpdateStateChanged+=RenderUpdateState;
            FormClosed+=(s,e)=>owner.UpdateStateChanged-=RenderUpdateState;
            Activated+=(s,e)=>ReadStartup();
            ReadStartup(); RenderUpdateState();
        }

        static void StyleButton(Button button,string text,int width) {
            button.Text=text; button.Width=width; button.Height=32; button.Margin=new Padding(0,0,8,0);
            button.FlatStyle=FlatStyle.Flat; button.FlatAppearance.BorderColor=Color.FromArgb(208,212,219); button.BackColor=Color.White;
        }
        void ReadStartup() {
            var state=WindowsStartup.Read(Application.ExecutablePath);
            loadingStartup=true; launchAtLogin.Checked=state.Enabled; loadingStartup=false;
            startupExplanation.Text=state.Error ?? (state.DifferentLocation?"已有启动项指向其他位置；勾选可改为当前应用位置。":"仅为当前用户设置，默认关闭。移动应用后需重新勾选。");
        }
        void SetStartup() {
            if(loadingStartup) return;
            try {
                WindowsStartup.SetEnabled(launchAtLogin.Checked,Application.ExecutablePath);
                preferenceStatus.Text="";
            } catch(InvalidOperationException error) { preferenceStatus.Text=error.Message; }
            ReadStartup();
        }
        void RenderUpdateState() {
            if(IsDisposed) return;
            check.Enabled=!owner.IsCheckingUpdates;
            download.Visible=owner.AvailableUpdate!=null;
            download.Enabled=!owner.IsCheckingUpdates;
            download.Text=owner.AvailableUpdate!=null && !owner.AvailableUpdate.HasDownload?"查看发布页":"下载更新";
            updateStatus.Text=owner.UpdateStatus;
        }
        void OpenRepository() {
            try { Process.Start(new ProcessStartInfo(GitHubUpdates.RepositoryURL) { UseShellExecute=true }); }
            catch(Exception error) {
                if(!(error is System.ComponentModel.Win32Exception || error is InvalidOperationException)) throw;
                preferenceStatus.Text="无法打开浏览器，请稍后重试。";
            }
        }
    }
}
