using System;
using Microsoft.Win32;

namespace CaptureAccess {
    internal sealed class StartupState {
        internal bool Enabled, DifferentLocation;
        internal string Error;
    }
    internal static class WindowsStartup {
        internal const string RunKey=@"Software\Microsoft\Windows\CurrentVersion\Run";
        internal const string ValueName="CaptureAccess";

        internal static string CommandFor(string executable) {
            if(String.IsNullOrWhiteSpace(executable) || executable.IndexOfAny(new[]{'"','\0','\r','\n'})>=0)
                throw new ArgumentException("应用路径无效，无法设置登录启动。");
            return "\""+executable+"\"";
        }
        internal static bool Matches(string command,string executable) {
            return String.Equals(command,CommandFor(executable),StringComparison.OrdinalIgnoreCase);
        }
        internal static StartupState Read(string executable) {
            try {
                using(var key=Registry.CurrentUser.OpenSubKey(RunKey,false)) {
                    string command=key==null?null:key.GetValue(ValueName,null,RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
                    bool enabled=command!=null && Matches(command,executable);
                    return new StartupState { Enabled=enabled,DifferentLocation=command!=null && !enabled };
                }
            } catch(Exception error) {
                if(!(error is UnauthorizedAccessException || error is System.Security.SecurityException || error is System.IO.IOException)) throw;
                return new StartupState { Error="无法读取登录启动设置，请检查当前用户的权限。" };
            }
        }
        internal static void SetEnabled(bool enabled,string executable) {
            try {
                if(enabled) {
                    using(var key=Registry.CurrentUser.CreateSubKey(RunKey)) {
                        if(key==null) throw new UnauthorizedAccessException();
                        key.SetValue(ValueName,CommandFor(executable),RegistryValueKind.String);
                    }
                } else {
                    using(var key=Registry.CurrentUser.OpenSubKey(RunKey,true)) {
                        if(key!=null) key.DeleteValue(ValueName,false);
                    }
                }
            } catch(Exception error) {
                if(!(error is UnauthorizedAccessException || error is System.Security.SecurityException || error is System.IO.IOException)) throw;
                throw new InvalidOperationException("未能更改登录启动设置。请检查当前用户的权限后重试。",error);
            }
        }
    }
}
