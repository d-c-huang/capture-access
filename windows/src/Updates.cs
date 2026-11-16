using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace CaptureAccess {
    internal sealed class ReleaseVersion : IComparable<ReleaseVersion> {
        internal readonly int Major, Minor, Patch;
        private ReleaseVersion(int major, int minor, int patch) { Major=major; Minor=minor; Patch=patch; }
        internal static bool TryParse(string text, out ReleaseVersion version) {
            version=null;
            if(String.IsNullOrEmpty(text)) return false;
            if(text[0]=='v' || text[0]=='V') text=text.Substring(1);
            string[] parts=text.Split('.');
            if(parts.Length!=3) return false;
            int[] values=new int[3];
            for(int i=0;i<3;i++) {
                if(parts[i].Length==0 || (parts[i].Length>1 && parts[i][0]=='0')) return false;
                foreach(char ch in parts[i]) if(ch<'0' || ch>'9') return false;
                if(!Int32.TryParse(parts[i], NumberStyles.None, CultureInfo.InvariantCulture, out values[i])) return false;
            }
            version=new ReleaseVersion(values[0],values[1],values[2]); return true;
        }
        public int CompareTo(ReleaseVersion other) {
            if(other==null) return 1;
            int result=Major.CompareTo(other.Major);
            if(result==0) result=Minor.CompareTo(other.Minor);
            return result==0?Patch.CompareTo(other.Patch):result;
        }
        public override string ToString() { return String.Format(CultureInfo.InvariantCulture,"{0}.{1}.{2}",Major,Minor,Patch); }
    }

    internal sealed class UpdateRelease {
        internal ReleaseVersion Version;
        internal string Tag;
        internal Uri DownloadURL, ReleaseURL;
        internal bool HasDownload { get { return DownloadURL!=null; } }
    }
    internal sealed class ReleaseAssetData {
        public string name { get; set; }
        public string browser_download_url { get; set; }
        public string state { get; set; }
        public long size { get; set; }
    }
    internal sealed class ReleaseData {
        public string tag_name { get; set; }
        public string html_url { get; set; }
        public bool? draft { get; set; }
        public bool? prerelease { get; set; }
        public List<ReleaseAssetData> assets { get; set; }
    }

    internal static class GitHubUpdates {
        internal const string CurrentVersion="0.8.0";
        internal const string RepositoryURL="https://github.com/d-c-huang/capture-access";
        internal const string LatestAPI="https://api.github.com/repos/d-c-huang/capture-access/releases/latest";
        internal const string AssetName="CaptureAccess-Windows.zip";
        const int MaximumResponseBytes=1024*1024;

        internal static Task<UpdateRelease> CheckAsync(CancellationToken cancellationToken) {
            return Task.Run(()=>Fetch(cancellationToken),cancellationToken);
        }

        static UpdateRelease Fetch(CancellationToken cancellationToken) {
            // .NET Framework 4.x on Windows 10/11 supports TLS 1.2. The numeric
            // value also compiles with the framework's bundled C# 5 compiler.
            ServicePointManager.SecurityProtocol=(SecurityProtocolType)3072;
            var request=(HttpWebRequest)WebRequest.Create(LatestAPI);
            request.Method="GET"; request.Accept="application/vnd.github+json";
            request.UserAgent="CaptureAccess-Windows/"+CurrentVersion;
            request.Headers["X-GitHub-Api-Version"]="2022-11-28";
            request.AllowAutoRedirect=false; request.Timeout=12000; request.ReadWriteTimeout=12000;
            request.UseDefaultCredentials=false;
            request.AutomaticDecompression=DecompressionMethods.GZip | DecompressionMethods.Deflate;
            using(var deadline=new CancellationTokenSource(12000))
            using(var stopped=CancellationTokenSource.CreateLinkedTokenSource(cancellationToken,deadline.Token))
            using(stopped.Token.Register(()=>request.Abort())) {
                try {
                    using(var response=(HttpWebResponse)request.GetResponse()) {
                        cancellationToken.ThrowIfCancellationRequested();
                        if(response.StatusCode!=HttpStatusCode.OK || response.ResponseUri.AbsoluteUri!=LatestAPI)
                            throw new InvalidDataException("更新服务返回了无法验证的响应，请稍后重试。");
                        if(response.ContentLength>MaximumResponseBytes) throw new InvalidDataException("更新信息过大，已停止读取。");
                        using(var source=response.GetResponseStream())
                        using(var bytes=new MemoryStream()) {
                            byte[] buffer=new byte[8192]; int count;
                            while((count=source.Read(buffer,0,buffer.Length))>0) {
                                cancellationToken.ThrowIfCancellationRequested();
                                if(bytes.Length+count>MaximumResponseBytes) throw new InvalidDataException("更新信息过大，已停止读取。");
                                bytes.Write(buffer,0,count);
                            }
                            return ParseRelease(Encoding.UTF8.GetString(bytes.ToArray()));
                        }
                    }
                } catch(WebException error) {
                    cancellationToken.ThrowIfCancellationRequested();
                    if(deadline.IsCancellationRequested) throw new InvalidDataException("检查更新超时，请检查网络后重试。");
                    var response=error.Response as HttpWebResponse;
                    if(response!=null) {
                        using(response) {
                            if(response.StatusCode==HttpStatusCode.NotFound)
                                throw new InvalidDataException("GitHub 暂无可用的正式版本，请稍后再检查。");
                            if(response.StatusCode==HttpStatusCode.Forbidden || (int)response.StatusCode==429)
                                throw new InvalidDataException("GitHub 暂时限制了更新查询，请稍后再试。");
                        }
                    }
                    if(error.Status==WebExceptionStatus.Timeout)
                        throw new InvalidDataException("检查更新超时，请检查网络后重试。");
                    throw new InvalidDataException("无法连接 GitHub 检查更新，请检查网络后重试。");
                } catch(IOException) {
                    cancellationToken.ThrowIfCancellationRequested();
                    if(deadline.IsCancellationRequested) throw new InvalidDataException("检查更新超时，请检查网络后重试。");
                    throw;
                }
            }
        }

        internal static UpdateRelease ParseRelease(string json) {
            ReleaseData data;
            try { data=new JavaScriptSerializer { MaxJsonLength=MaximumResponseBytes }.Deserialize<ReleaseData>(json); }
            catch(Exception error) {
                if(error is ArgumentException || error is InvalidOperationException)
                    throw new InvalidDataException("无法读取 GitHub 的版本信息。");
                throw;
            }
            ReleaseVersion version;
            if(data==null || data.draft!=false || data.prerelease!=false || !ReleaseVersion.TryParse(data.tag_name,out version))
                throw new InvalidDataException("GitHub 返回的不是可识别的正式版本。");
            Uri releaseURL;
            if(!TryReleaseURL(data.html_url,data.tag_name,out releaseURL))
                throw new InvalidDataException("发布页地址不属于本项目，已停止更新查询。");
            Uri download=null; int matchingAssets=0;
            if(data.assets!=null) foreach(var asset in data.assets) {
                if(asset==null || asset.name!=AssetName) continue;
                matchingAssets++;
                Uri candidate;
                if(asset.state=="uploaded" && asset.size>0 && TryDownloadURL(asset.browser_download_url,data.tag_name,out candidate))
                    download=candidate;
            }
            // Duplicate assets are ambiguous. Missing/invalid platform assets
            // can only open the verified release page, never another product.
            if(matchingAssets!=1) download=null;
            return new UpdateRelease { Version=version, Tag=data.tag_name, ReleaseURL=releaseURL, DownloadURL=download };
        }

        internal static bool TryDownloadURL(string text,string tag,out Uri result) {
            return ExactURL(text,RepositoryURL+"/releases/download/"+Uri.EscapeDataString(tag)+"/"+AssetName,out result);
        }
        internal static bool TryReleaseURL(string text,string tag,out Uri result) {
            return ExactURL(text,RepositoryURL+"/releases/tag/"+Uri.EscapeDataString(tag),out result);
        }
        static bool ExactURL(string text,string expected,out Uri result) {
            result=null; Uri candidate;
            if(!String.Equals(text,expected,StringComparison.Ordinal) || !Uri.TryCreate(text,UriKind.Absolute,out candidate)
                || candidate.Scheme!="https" || candidate.Host!="github.com" || !candidate.IsDefaultPort
                || candidate.UserInfo.Length!=0 || candidate.Query.Length!=0 || candidate.Fragment.Length!=0) return false;
            result=candidate; return true;
        }
    }

    internal sealed class UpdatePreferencesData {
        public bool? automaticChecks { get; set; }
        public long lastCheckUtcTicks { get; set; }
    }
    internal sealed class UpdatePreferences {
        readonly string path;
        internal bool AutomaticChecks=true;
        internal DateTime? LastCheckUTC;
        internal string LastSaveError;

        internal UpdatePreferences(string storagePath) {
            path=storagePath;
            try {
                if(!File.Exists(path)) return;
                if(new FileInfo(path).Length>4096) return;
                var data=new JavaScriptSerializer().Deserialize<UpdatePreferencesData>(File.ReadAllText(path));
                if(data==null) return;
                AutomaticChecks=data.automaticChecks ?? true;
                if(data.lastCheckUtcTicks>0 && data.lastCheckUtcTicks<=DateTime.MaxValue.Ticks)
                    LastCheckUTC=new DateTime(data.lastCheckUtcTicks,DateTimeKind.Utc);
            } catch(Exception error) {
                if(!(error is IOException || error is UnauthorizedAccessException || error is ArgumentException || error is InvalidOperationException)) throw;
            }
        }
        internal static UpdatePreferences LoadDefault() {
            return new UpdatePreferences(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CaptureAccess","updates.json"));
        }
        internal bool ShouldCheck(DateTime utcNow) {
            return AutomaticChecks && (!LastCheckUTC.HasValue || LastCheckUTC.Value>utcNow || utcNow-LastCheckUTC.Value>=TimeSpan.FromDays(1));
        }
        internal void RecordAttempt(DateTime utcNow) { LastCheckUTC=utcNow.ToUniversalTime(); Save(); }
        internal void Save() {
            string temporary=path+"."+Guid.NewGuid().ToString("N")+".tmp";
            try {
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                var data=new UpdatePreferencesData { automaticChecks=AutomaticChecks,lastCheckUtcTicks=LastCheckUTC.HasValue?LastCheckUTC.Value.Ticks:0 };
                File.WriteAllText(temporary,new JavaScriptSerializer().Serialize(data),new UTF8Encoding(false));
                if(File.Exists(path)) File.Replace(temporary,path,null);
                else File.Move(temporary,path);
                LastSaveError=null;
            } catch(Exception error) {
                if(!(error is IOException || error is UnauthorizedAccessException)) throw;
                LastSaveError="更新偏好未能保存，本次选择仅在当前运行期间生效。";
            } finally {
                try { if(File.Exists(temporary)) File.Delete(temporary); } catch(IOException) { } catch(UnauthorizedAccessException) { }
            }
        }
    }
}
