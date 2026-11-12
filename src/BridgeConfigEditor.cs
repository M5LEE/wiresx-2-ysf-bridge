using System;
using System.IO;
using System.Drawing;
using System.Windows.Forms;
using System.ComponentModel;
using System.Diagnostics;
using System.Collections.Generic;
using System.Text;
using System.Web.Script.Serialization;
using CumbriaCQ.Catalog;
using CumbriaCQ.Configuration;
using ReflectorCatalog=CumbriaCQ.Catalog.Catalog;

static class BridgeEditorProgram {
 [STAThread] static void Main(string[] args){
  Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
  string root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),@"M5LEE\WIRESX-to-YSF-Brtidge");Directory.CreateDirectory(root);
  try{
   if(args.Length==1 && args[0]=="--launcher"){
    var principal=new System.Security.Principal.WindowsPrincipal(System.Security.Principal.WindowsIdentity.GetCurrent());
    if(!principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator)){
     Process.Start(new ProcessStartInfo(Application.ExecutablePath,"--launcher") {UseShellExecute=true,Verb="runas"});return;
    }
    Application.Run(new LauncherForm(AppDomain.CurrentDomain.BaseDirectory));return;
   }
   if(args.Length==1 && args[0]=="--setup"){
    Process.Start(new ProcessStartInfo("powershell.exe","-NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"station-setup.ps1")+"\"") {UseShellExecute=true,Verb="runas"});return;
   }
   if(args.Length==2 && args[0]=="--smoke-test"){
    string dir=Path.GetFullPath(args[1]);Directory.CreateDirectory(dir);root=dir;
    Application.Run(new ConfigForm(root,Path.Combine(dir,"bridge-config.json"),dir));return;
   }
   if(args.Length!=0)throw new ArgumentException("Expected no arguments, --launcher, or --smoke-test DIRECTORY");
   Application.Run(new ConfigForm(root,Path.Combine(root,"bridge-config.json"),null));
  }catch(Exception e){MessageBox.Show(e.Message,"WiresX 2 YSF Bridge",MessageBoxButtons.OK,MessageBoxIcon.Error);Environment.ExitCode=1;}
 }
}

sealed class ConfigForm:Form {
 readonly string root,path,cache,smoke;
 ConfigSession session;CatalogSnapshot catalog;Room selected;bool filling,busy;
 readonly TextBox search=new TextBox();readonly ListView list=new ListView();
 readonly Label cacheInfo=new Label(),selection=new Label(),status=new Label();
 readonly NumericUpDown dg=new NumericUpDown();readonly CheckBox zero=new CheckBox();
 readonly Button refresh=new Button(),save=new Button();readonly ProgressBar progress=new ProgressBar();
 public ConfigForm(string root,string path,string smoke){
  this.root=root;this.path=path;this.smoke=smoke;cache=Path.Combine(root,"room-cache","catalog.json");
  Icon=new System.Drawing.Icon(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"assets","settings.ico"));
  Text="WiresX 2 YSF Bridge - Configuration";Font=new Font("Segoe UI",9F);StartPosition=FormStartPosition.CenterScreen;ClientSize=new Size(940,625);MinimumSize=new Size(820,580);AutoScaleMode=AutoScaleMode.Dpi;
  var layout=new TableLayoutPanel {Dock=DockStyle.Fill,Padding=new Padding(16),ColumnCount=1,RowCount=8};Controls.Add(layout);
  layout.RowStyles.Add(new RowStyle(SizeType.Absolute,36));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,36));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,32));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,62));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,38));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,48));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,40));
  layout.Controls.Add(new Label {Text="YSF reflector settings - ALPHA",Font=new Font(Font.FontFamily,15F,FontStyle.Bold),Dock=DockStyle.Fill},0,0);
  var filter=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=3};filter.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,82));filter.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));filter.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,155));
  filter.Controls.Add(new Label {Text="Find room",AutoSize=true,Anchor=AnchorStyles.Left},0,0);search.Dock=DockStyle.Fill;search.Margin=new Padding(3,4,12,3);filter.Controls.Add(search,1,0);refresh.Text="Update YSF list";refresh.Dock=DockStyle.Fill;filter.Controls.Add(refresh,2,0);layout.Controls.Add(filter,0,1);
  cacheInfo.Dock=DockStyle.Fill;cacheInfo.ForeColor=Color.DimGray;layout.Controls.Add(cacheInfo,0,2);
  list.Dock=DockStyle.Fill;list.View=View.Details;list.FullRowSelect=true;list.HideSelection=false;list.MultiSelect=false;list.ShowItemToolTips=true;
  list.Columns.Add("YSF ID",70);list.Columns.Add("Full room name",210);list.Columns.Add("Country",65);list.Columns.Add("Host",210);list.Columns.Add("UDP",65);list.Columns.Add("Description",250);layout.Controls.Add(list,0,3);
  selection.Dock=DockStyle.Fill;selection.Padding=new Padding(0,7,0,0);layout.Controls.Add(selection,0,4);
  var options=new FlowLayoutPanel {Dock=DockStyle.Fill,WrapContents=false};options.Controls.Add(new Label {Text="DG-ID",AutoSize=true,Margin=new Padding(0,7,8,0)});dg.Minimum=0;dg.Maximum=127;dg.Width=70;options.Controls.Add(dg);zero.Text="Accept DG-ID 0 from this reflector";zero.AutoSize=true;zero.Margin=new Padding(20,6,0,0);options.Controls.Add(zero);layout.Controls.Add(options,0,5);
  layout.Controls.Add(new Label {Text="Saved changes apply on the NEXT bridge start. AS IS; optional donations via Help below.\r\nThis selects a YSF reflector only. Station setup selects your own WIRES-X room. Radio safety settings stay unchanged.",Dock=DockStyle.Fill,ForeColor=Color.DimGray},0,6);
  var bottom=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=5};bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));for(int i=0;i<4;i++)bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,116));
  status.Dock=DockStyle.Fill;status.AutoEllipsis=true;bottom.Controls.Add(status,0,0);
  var reload=new Button {Text="Station setup",Dock=DockStyle.Fill};bottom.Controls.Add(reload,1,0);var launcher=new Button {Text="Launcher...",Dock=DockStyle.Fill};bottom.Controls.Add(launcher,2,0);save.Text="Save config";save.Dock=DockStyle.Fill;bottom.Controls.Add(save,3,0);var close=new Button {Text="Close",Dock=DockStyle.Fill};bottom.Controls.Add(close,4,0);layout.Controls.Add(bottom,0,7);
  progress.Dock=DockStyle.Bottom;progress.Height=3;progress.Style=ProgressBarStyle.Marquee;progress.Visible=false;Controls.Add(progress);
  search.TextChanged+=delegate{FillRooms();};list.SelectedIndexChanged+=delegate{SelectRoom();};refresh.Click+=delegate{RefreshCatalog(null);};save.Click+=delegate{SaveSettings();};close.Click+=delegate{Close();};cacheInfo.Cursor=Cursors.Hand;cacheInfo.AccessibleDescription="Optional CumbriaCQ support: click to open donation information";cacheInfo.Click+=delegate{Process.Start(new ProcessStartInfo("https://cumbriacq.com/donate-support/") {UseShellExecute=true});};reload.Click+=delegate{Process.Start(new ProcessStartInfo(Application.ExecutablePath,"--setup") {UseShellExecute=true});};launcher.Click+=delegate{Process.Start(new ProcessStartInfo(Application.ExecutablePath,"--launcher") {UseShellExecute=true});};
  FormClosing+=delegate(object sender,FormClosingEventArgs e){if(busy){e.Cancel=true;status.Text="Please wait for the bounded list update to finish.";}};
  LoadSettings();TryLoadCatalog();
  Shown+=delegate{if(smoke!=null)BeginInvoke(new Action(delegate{RefreshCatalog(SmokeFinish);}));};
 }
 void LoadSettings(){session=SettingsStore.Open(path);dg.Value=session.Settings.DgId;zero.Checked=session.Settings.AllowZeroDg;status.Text="Saved target: "+session.Settings.YsfRoomId+" "+session.Settings.YsfRoomName;}
 void TryLoadCatalog(){try{catalog=CatalogView.Load(cache);cacheInfo.Text=String.Format("Pi-Star / DVRef-derived list: {0} rooms | Updated {1:yyyy-MM-dd HH:mm} UTC{2}",catalog.Rooms.Count,catalog.FetchedAtUtc,DateTime.UtcNow-catalog.FetchedAtUtc>TimeSpan.FromDays(1)?" | Update recommended":"");FillRooms();}catch(Exception e){catalog=null;list.Items.Clear();save.Enabled=false;cacheInfo.Text="No usable local list. Click Update YSF list. "+e.Message;}}
 void FillRooms(){
  filling=true;list.BeginUpdate();list.Items.Clear();selected=null;
  if(catalog!=null)foreach(var room in CatalogView.Filter(catalog.Rooms,search.Text)){
   var item=new ListViewItem(new[]{room.Id,room.Name,room.Country,room.Host,room.Port.ToString(),room.Description});item.Tag=room;item.ToolTipText=room.Name+"\n"+room.Description;list.Items.Add(item);
   if(room.Id==session.Settings.YsfRoomId && room.Host==session.Settings.YsfHost && room.Port==session.Settings.YsfPort)item.Selected=true;
  }
  list.EndUpdate();filling=false;SelectRoom();
 }
 void SelectRoom(){
  if(filling)return;selected=list.SelectedItems.Count==1?list.SelectedItems[0].Tag as Room:null;save.Enabled=selected!=null && !busy;
  if(selected==null){selection.Text="Select a reflector to see its full endpoint and save it.";return;}
  selection.Text=selected.Id+"  "+selected.Name+"\r\n"+selected.Host+":"+selected.Port+"  "+selected.Description;
  bool same=selected.Id==session.Settings.YsfRoomId && selected.Host==session.Settings.YsfHost && selected.Port==session.Settings.YsfPort;
  dg.Value=same?session.Settings.DgId:0;zero.Checked=same && session.Settings.AllowZeroDg;
 }
 bool SaveSettings(){try{
  if(selected==null)throw new ArgumentException("Select a reflector first");
  var settings=new BridgeSettings {SchemaVersion=1,YsfRoomId=selected.Id,YsfRoomName=selected.Name,YsfHost=selected.Host,YsfPort=selected.Port,DgId=(int)dg.Value,AllowZeroDg=zero.Checked};
  string backup=SettingsStore.Save(path,settings,session.Fingerprint);session=SettingsStore.Open(path);status.Text="Saved for next start"+(backup.Length>0?"; backup kept.":".");return true;
 }catch(Exception e){Failure(e);return false;}}
 void Failure(Exception e){status.Text=e.Message;if(smoke==null)MessageBox.Show(this,e.Message,"Configuration not changed",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
 void RefreshCatalog(Action<bool> finished){
  if(busy)return;busy=true;refresh.Enabled=false;save.Enabled=false;progress.Visible=true;status.Text="Downloading and validating reflector list...";
  var worker=new BackgroundWorker();worker.DoWork+=delegate{ReflectorCatalog.Refresh(cache);};
  worker.RunWorkerCompleted+=delegate(object sender,RunWorkerCompletedEventArgs e){
   busy=false;progress.Visible=false;refresh.Enabled=true;TryLoadCatalog();status.Text=e.Error==null?"Reflector list updated.":"Update failed; previous list retained.";
   if(e.Error!=null && smoke==null)MessageBox.Show(this,e.Error.Message,"YSF list update",MessageBoxButtons.OK,MessageBoxIcon.Warning);
   worker.Dispose();if(finished!=null)finished(e.Error==null);
  };worker.RunWorkerAsync();
 }
 void SmokeFinish(bool updated){
  var result=new Dictionary<string,object>();
  try{
   if(catalog==null)throw new Exception("No catalogue available for UI smoke test");search.Text="cumbria";int matched=list.Items.Count;bool found=false;
   foreach(ListViewItem item in list.Items)if(((Room)item.Tag).Id=="00041"){item.Selected=true;item.EnsureVisible();found=true;break;}
   SelectRoom();if(!found || selected==null)throw new Exception("Expected leading-zero room unavailable");
   save.PerformClick();var reopened=SettingsStore.Open(path);if(reopened.Settings.YsfRoomId!="00041" || !File.Exists(path))throw new Exception("UI save failed");
   string screenshot=Path.Combine(smoke,"config-editor.png");using(var bitmap=new Bitmap(Width,Height)){DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height));bitmap.Save(screenshot,System.Drawing.Imaging.ImageFormat.Png);}
   result["Pass"]=true;result["UpdateSucceeded"]=updated;result["CatalogCount"]=catalog.Rooms.Count;result["SearchMatches"]=matched;result["SavedRoomId"]=reopened.Settings.YsfRoomId;result["SavedHost"]=reopened.Settings.YsfHost;result["ConfigPath"]=path;result["Screenshot"]=screenshot;result["NoRadioOrBridgeActions"]=true;
  }catch(Exception e){result["Pass"]=false;result["Error"]=e.ToString();Environment.ExitCode=1;}
  File.WriteAllText(Path.Combine(smoke,"smoke-result.json"),new JavaScriptSerializer().Serialize(result));
  var timer=new Timer {Interval=1200};timer.Tick+=delegate{timer.Stop();timer.Dispose();Close();};timer.Start();
 }
}

sealed class LauncherForm:Form {
 readonly string root;readonly TextBox output=new TextBox();readonly Button check=new Button(),start=new Button(),stop=new Button();bool busy;
 public LauncherForm(string root){
  Icon=System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
  this.root=root;Text="WiresX 2 YSF Bridge - Launcher";Font=new Font("Segoe UI",9F);StartPosition=FormStartPosition.CenterScreen;ClientSize=new Size(680,330);MinimumSize=new Size(600,300);
  var layout=new TableLayoutPanel {Dock=DockStyle.Fill,Padding=new Padding(16),ColumnCount=1,RowCount=4};Controls.Add(layout);layout.RowStyles.Add(new RowStyle(SizeType.Absolute,35));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,46));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,42));
  layout.Controls.Add(new Label {Text="Bridge startup and stop",Font=new Font(Font.FontFamily,14F,FontStyle.Bold),Dock=DockStyle.Fill},0,0);
  layout.Controls.Add(new Label {Text="Start puts the adapter before WIRES-X and checks for an existing test.\r\nFive-hour alpha sessions. Keep the FTM off. Closing this window is not Stop.",Dock=DockStyle.Fill},0,1);
  output.Multiline=true;output.ReadOnly=true;output.ScrollBars=ScrollBars.Vertical;output.Dock=DockStyle.Fill;layout.Controls.Add(output,0,2);
  var buttons=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.LeftToRight};start.Text="Start bridge";start.AutoSize=true;start.Enabled=false;stop.Text="Stop launched bridge";stop.AutoSize=true;stop.Enabled=false;var config=new Button {Text="Configuration...",AutoSize=true};check.Text="Refresh status";check.AutoSize=true;buttons.Controls.AddRange(new Control[]{start,stop,config,check});layout.Controls.Add(buttons,0,3);
  start.Click+=delegate{Action("Start");};stop.Click+=delegate{if(MessageBox.Show(this,"Stop the bridge owned by this launcher? Other test sessions will not be force-stopped.","Stop bridge",MessageBoxButtons.YesNo,MessageBoxIcon.Question)==DialogResult.Yes)Action("Stop");};config.Click+=delegate{Process.Start(new ProcessStartInfo(Application.ExecutablePath) {UseShellExecute=true});};check.Click+=delegate{CheckStatus();};Shown+=delegate{CheckStatus();};
 }
 void Action(string action){try{
  string script=Path.Combine(root,"BridgeSupervisor.ps1");if(!File.Exists(script))throw new FileNotFoundException("Launcher backend not installed",script);
  Process.Start(new ProcessStartInfo("powershell.exe","-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+script+"\" -"+action) {UseShellExecute=true,Verb="runas",WindowStyle=ProcessWindowStyle.Hidden,WorkingDirectory=root});
  output.Text="Requested "+action.ToLowerInvariant()+". Use Refresh status to verify; startup may take several minutes.";
  start.Enabled=false;stop.Enabled=false;var timer=new Timer {Interval=3000};timer.Tick+=delegate{timer.Stop();timer.Dispose();if(!IsDisposed)CheckStatus();};timer.Start();
 }catch(Exception e){MessageBox.Show(this,e.Message,"Launcher",MessageBoxButtons.OK,MessageBoxIcon.Warning);}}
 void CheckStatus(){
  if(busy)return;busy=true;check.Enabled=false;start.Enabled=false;stop.Enabled=false;var worker=new BackgroundWorker();
  worker.DoWork+=delegate(object sender,DoWorkEventArgs e){
   string script=Path.Combine(root,"BridgeSupervisor.ps1");if(!File.Exists(script)){e.Result="Launcher backend has not been installed.";return;}
   var text=new StringBuilder();using(var p=new Process()){
    p.StartInfo=new ProcessStartInfo("powershell.exe","-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+script+"\" -CheckOnly") {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
    DataReceivedEventHandler append=delegate(object source,DataReceivedEventArgs row){if(row.Data!=null)lock(text){if(text.Length<12000)text.AppendLine(row.Data);}};p.OutputDataReceived+=append;p.ErrorDataReceived+=append;p.Start();p.BeginOutputReadLine();p.BeginErrorReadLine();if(!p.WaitForExit(20000)){p.Kill();throw new TimeoutException("Status check timed out");}p.WaitForExit();e.Result=text.ToString();
   }
  };worker.RunWorkerCompleted+=delegate(object sender,RunWorkerCompletedEventArgs e){busy=false;if(!IsDisposed){
   check.Enabled=true;output.Text=e.Error==null?Convert.ToString(e.Result):e.Error.Message;
   if(e.Error==null)try{
    string[] lines=output.Text.Trim().Split('\n');var response=new JavaScriptSerializer().DeserializeObject(lines[lines.Length-1]) as Dictionary<string,object>;
    if(response==null || !Object.Equals(response["Event"],"Check"))throw new Exception("Status unavailable");
    var data=(Dictionary<string,object>)response["Data"];bool existing=(bool)data["ExistingBridge"],owner=(bool)data["OwnerManifestPresent"];
    bool setupReady=data.ContainsKey("SetupReady") && Object.Equals(data["SetupReady"],true);start.Enabled=!existing && !owner && setupReady;stop.Enabled=existing && owner;
    string heading=existing?(owner?"Bridge present; launcher ownership record present.":"Existing test is running.\r\nStart/Stop are disabled here because this launcher does not own that session."):(owner?"Retained ownership record: inspect cleanup before another start.":(setupReady?"Ready to start. Keep the FTM off; startup may take several minutes.":"Station setup and your own validated radio profile are required before Start."));
    output.Text=heading+"\r\n\r\n"+output.Text;
   }catch{start.Enabled=false;stop.Enabled=false;}
  }worker.Dispose();};worker.RunWorkerAsync();
 }
}
