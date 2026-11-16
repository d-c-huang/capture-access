using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;
using CaptureAccess;

static class UpdateTests {
    static int assertions;
    static void Check(bool condition,string message) { if(!condition) throw new Exception("FAIL: "+message); assertions++; }
    static void Reject(Action action,string message) {
        bool rejected=false; try { action(); } catch(InvalidDataException) { rejected=true; }
        Check(rejected,message);
    }
    static string Release(string tag="v0.9.0",object[] assets=null,bool draft=false,bool prerelease=false,string page=null) {
        return new JavaScriptSerializer().Serialize(new {
            tag_name=tag,draft=draft,prerelease=prerelease,
            html_url=page ?? GitHubUpdates.RepositoryURL+"/releases/tag/"+tag,
            assets=assets ?? new object[]{Asset(GitHubUpdates.RepositoryURL+"/releases/download/"+tag+"/"+GitHubUpdates.AssetName)}
        });
    }
    static object Asset(string url,string name=GitHubUpdates.AssetName,string state="uploaded",long size=2048) {
        return new {name=name,browser_download_url=url,state=state,size=size};
    }
    static void Main() {
        ReleaseVersion oldVersion,newVersion;
        Check(ReleaseVersion.TryParse("v0.9.9",out oldVersion) && ReleaseVersion.TryParse("0.10.0",out newVersion) && newVersion.CompareTo(oldVersion)>0,"numeric minor version comparison");
        Check(ReleaseVersion.TryParse("V2.0.0",out newVersion) && newVersion.CompareTo(oldVersion)>0,"major version comparison");
        Check(ReleaseVersion.TryParse("0.9.9",out newVersion) && newVersion.CompareTo(oldVersion)==0,"equal version comparison");
        foreach(string text in new[]{"", "v", "1.0", "v1.0.0-beta", "1.0.0+build", "1.0.0.0", "01.0.0", "1.-1.0", " 1.0.0", "1.0.0 ", "2147483648.0.0", "1.0.x"}) {
            ReleaseVersion ignored; Check(!ReleaseVersion.TryParse(text,out ignored),"reject malformed/nonstable tag: "+text);
        }
        var valid=GitHubUpdates.ParseRelease(Release());
        Check(valid.HasDownload && valid.Version.ToString()=="0.9.0","matching Windows package found");
        Check(valid.DownloadURL.AbsoluteUri.EndsWith("/v0.9.0/CaptureAccess-Windows.zip"),"exact platform asset URL retained");
        Check(valid.ReleaseURL.AbsoluteUri==GitHubUpdates.RepositoryURL+"/releases/tag/v0.9.0","verified release page retained");
        Reject(()=>GitHubUpdates.ParseRelease(Release(draft:true)),"ignore draft releases");
        Reject(()=>GitHubUpdates.ParseRelease(Release(prerelease:true)),"ignore prereleases");
        Reject(()=>GitHubUpdates.ParseRelease(Release(tag:"v1.0.0-beta")),"ignore prerelease tag even if metadata flag false");
        Reject(()=>GitHubUpdates.ParseRelease(Release(page:"https://example.invalid/release")),"reject unrelated release page");
        Reject(()=>GitHubUpdates.ParseRelease("{not-json}"),"reject malformed JSON");
        Reject(()=>GitHubUpdates.ParseRelease("null"),"reject null JSON");
        Reject(()=>GitHubUpdates.ParseRelease("{\"tag_name\":\"v1.0.0\"}"),"require explicit stable-release flags");
        string good=GitHubUpdates.RepositoryURL+"/releases/download/v0.9.0/"+GitHubUpdates.AssetName;
        string[] badURLs={
            good.Replace("https:","http:"), good+"?token=example", good+"#fragment",
            good.Replace("github.com/","github.com.example.invalid/"),good.Replace("github.com/","github.com@evil.invalid/"),
            good.Replace("d-c-huang/capture-access","other/capture-access"),good.Replace("v0.9.0/","v0.8.0/"),
            good.Replace("CaptureAccess-Windows.zip","CaptureAccess-macOS-universal.zip"),
            good.Replace("/v0.9.0/","/v0.9.0/../v0.9.0/")," "+good,good.Replace("github.com/","github.com:444/")
        };
        foreach(string url in badURLs) Check(!GitHubUpdates.ParseRelease(Release(assets:new[]{Asset(url)})).HasDownload,"unsafe asset only allows verified release page");
        Check(!GitHubUpdates.ParseRelease(Release(assets:new[]{Asset(good,name:"CaptureAccess-macOS-universal.zip")})).HasDownload,"do not use another platform's package");
        Check(!GitHubUpdates.ParseRelease(Release(assets:new object[0])).HasDownload,"missing Windows package offers release page");
        Check(!GitHubUpdates.ParseRelease(Release(assets:new[]{Asset(good),Asset(good)})).HasDownload,"duplicate platform assets are ambiguous");
        Check(!GitHubUpdates.ParseRelease(Release(assets:new[]{Asset(good,state:"new")})).HasDownload,"do not download incomplete asset");
        Check(!GitHubUpdates.ParseRelease(Release(assets:new[]{Asset(good,size:0)})).HasDownload,"do not download empty asset");

        string directory=Path.Combine(Path.GetTempPath(),"CaptureAccessUpdateTests-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try {
            string path=Path.Combine(directory,"updates.json");
            DateTime now=new DateTime(2026,11,16,12,0,0,DateTimeKind.Utc);
            var options=new UpdatePreferences(path);
            Check(options.AutomaticChecks && options.ShouldCheck(now),"first launch defaults to auto-check");
            options.RecordAttempt(now);
            Check(options.LastSaveError==null && !options.ShouldCheck(now.AddHours(23)),"attempt recorded; no repeated daily request");
            Check(options.ShouldCheck(now.AddHours(24)),"daily check resumes after 24 hours");
            var reloaded=new UpdatePreferences(path);
            Check(reloaded.LastCheckUTC==now && !reloaded.ShouldCheck(now.AddHours(1)),"last attempt persists across launch");
            options.AutomaticChecks=false; options.Save();
            Check(!new UpdatePreferences(path).AutomaticChecks && !options.ShouldCheck(now.AddDays(10)),"disabled auto-check persists");
            options.AutomaticChecks=true; options.LastCheckUTC=now.AddDays(3);
            Check(options.ShouldCheck(now),"future clock date cannot permanently suppress checking");
            File.WriteAllText(path,"not-json");
            Check(new UpdatePreferences(path).AutomaticChecks,"corrupt preferences recover to defaults");
            string blocker=Path.Combine(directory,"blocked"); File.WriteAllText(blocker,"file");
            var unavailable=new UpdatePreferences(Path.Combine(blocker,"updates.json")); unavailable.AutomaticChecks=false; unavailable.Save();
            Check(unavailable.LastSaveError!=null && !unavailable.AutomaticChecks,"unwritable preferences preserve current in-memory choice");
        } finally { Directory.Delete(directory,true); }

        string executable=@"C:\Program Files\Capture Access\CaptureAccess.exe";
        Check(WindowsStartup.CommandFor(executable)=="\""+executable+"\"","startup executable with spaces is quoted");
        Check(WindowsStartup.Matches("\""+executable.ToUpperInvariant()+"\"",executable),"startup path comparison respects Windows case insensitivity");
        Check(!WindowsStartup.Matches("\""+executable+"\" --extra",executable),"startup matcher rejects extra arguments");
        Check(!WindowsStartup.Matches(WindowsStartup.CommandFor(@"C:\Old Location\CaptureAccess.exe"),executable),"moved executable does not falsely report enabled");
        bool badPathRejected=false; try { WindowsStartup.CommandFor("C:\\bad\"name.exe"); } catch(ArgumentException) { badPathRejected=true; }
        Check(badPathRejected,"startup command rejects embedded quotation marks");
        Check(WindowsStartup.ValueName=="CaptureAccess" && WindowsStartup.RunKey==@"Software\Microsoft\Windows\CurrentVersion\Run","startup scope uses only own current-user Run entry");
        Console.WriteLine("PASS: "+assertions+" updater/preferences/startup assertions (no network or Run registry writes)");
    }
}
