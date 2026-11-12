// Copyright (c) 2026 M5LEE. MIT; see LICENSE.
using System;
using System.IO;
using System.Drawing;
using System.Windows.Forms;
using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using System.Runtime.InteropServices;

sealed class LauncherForm:Form {
 readonly string root;
 readonly Func<string> statusProvider;
 readonly BridgeStatusWorker statusWorker;
 readonly Action<string> actionHook;
 readonly Func<string,string> startupHook;
 readonly Label headline=new Label(),summary=new Label();
 readonly TextBox output=new TextBox();
 readonly Button check=new Button(),start=new Button(),stop=new Button();
 readonly CheckBox startupBox=new CheckBox();
 readonly Label startupInfo=new Label();
 readonly NotifyIcon tray=new NotifyIcon();
 readonly ToolStripMenuItem openItem=new ToolStripMenuItem("Open status"),startItem=new ToolStripMenuItem("Start bridge"),stopItem=new ToolStripMenuItem("Stop bridge"),exitItem=new ToolStripMenuItem("Exit status app (bridge stays running)");
 readonly Timer refreshTimer=new Timer {Interval=5000};
 readonly Icon originalIcon;
 Icon statusIcon;
 string iconCode,lastActionError;
 bool busy,changingStartup,applyingStatus,autoPending,allowClose;
 DateTime pendingStartUntil=DateTime.MinValue;
 [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr handle);
 public LauncherForm(string root):this(root,false,null,null,null){}
 public LauncherForm(string root,bool autoStart,Func<string> readStatus,Action<string> actionHook,Func<string,string> startupHook){
  this.root=Path.GetFullPath(root);statusProvider=readStatus;this.actionHook=actionHook;this.startupHook=startupHook;autoPending=autoStart;
  if(readStatus==null)statusWorker=new BridgeStatusWorker(this.root,25000);
  originalIcon=new Icon(Path.Combine(root,"assets","bridge.ico"));Icon=(Icon)originalIcon.Clone();
  Text="WiresX 2 YSF Bridge - Checking";Font=new Font("Segoe UI",10F);StartPosition=FormStartPosition.CenterScreen;ClientSize=new Size(790,490);MinimumSize=new Size(730,460);AutoScaleMode=AutoScaleMode.Dpi;
  var layout=new TableLayoutPanel {Dock=DockStyle.Fill,Padding=new Padding(18),ColumnCount=1,RowCount=7};Controls.Add(layout);
  foreach(float height in new float[]{44,58,136,56,38,54,48})layout.RowStyles.Add(new RowStyle(SizeType.Absolute,height));
  headline.Text="Checking";headline.Name="BridgeStatus";headline.AccessibleName="Bridge status";headline.Font=new Font(Font.FontFamily,21F,FontStyle.Bold);headline.Dock=DockStyle.Fill;layout.Controls.Add(headline,0,0);
  summary.Text="Reading bridge status...";summary.Dock=DockStyle.Fill;layout.Controls.Add(summary,0,1);
  output.Multiline=true;output.ReadOnly=true;output.ScrollBars=ScrollBars.Vertical;output.Dock=DockStyle.Fill;output.AccessibleName="Bridge connection details";output.BackColor=SystemColors.Window;layout.Controls.Add(output,0,2);
  layout.Controls.Add(new Label {Text="WIRES-X must already be configured. The bridge follows its currently connected room.\r\nKeep the FTM off. Closing or minimising this window hides it to the tray; it does not stop the bridge.",Dock=DockStyle.Fill,ForeColor=Color.DimGray},0,3);
  startupBox.Text="Start bridge and WIRES-X automatically when I sign in to Windows";startupBox.AutoSize=true;startupBox.Dock=DockStyle.Fill;startupBox.Enabled=false;layout.Controls.Add(startupBox,0,4);
  startupInfo.Dock=DockStyle.Fill;startupInfo.ForeColor=Color.DimGray;startupInfo.Text="Sign-in startup is optional. Windows automatic sign-in is never configured.";layout.Controls.Add(startupInfo,0,5);
  var buttons=new FlowLayoutPanel {Dock=DockStyle.Fill,WrapContents=false};start.Text="Start bridge";start.AutoSize=true;start.Enabled=false;stop.Text="Stop bridge";stop.AutoSize=true;stop.Enabled=false;check.Text="Refresh status";check.AutoSize=true;var config=new Button {Text="YSF settings",AutoSize=true};var setup=new Button {Text="Station setup",AutoSize=true};buttons.Controls.AddRange(new Control[]{start,stop,check,config,setup});layout.Controls.Add(buttons,0,6);
  var menu=new ContextMenuStrip();menu.Items.AddRange(new ToolStripItem[]{openItem,startItem,stopItem,new ToolStripSeparator(),exitItem});tray.ContextMenuStrip=menu;tray.Icon=originalIcon;tray.Text="WiresX 2 YSF Bridge - Checking";tray.Visible=true;
  openItem.Click+=delegate{OpenStatus();};tray.DoubleClick+=delegate{OpenStatus();};startItem.Click+=delegate{if(start.Enabled)Action("Start");};stopItem.Click+=delegate{if(stop.Enabled)ConfirmStop();};exitItem.Click+=delegate{ExitStatus();};
  start.Click+=delegate{Action("Start");};stop.Click+=delegate{ConfirmStop();};check.Click+=delegate{CheckStatus();};
  config.Click+=delegate{Process.Start(new ProcessStartInfo(Path.Combine(root,"Bridge.exe")) {UseShellExecute=true});};setup.Click+=delegate{Process.Start(new ProcessStartInfo(Path.Combine(root,"Bridge.exe"),"--setup") {UseShellExecute=true});};
  startupBox.CheckedChanged+=delegate{if(!applyingStatus)ChangeStartup();};
  Shown+=delegate{if(autoPending)Hide();CheckStatus();};Resize+=delegate{if(WindowState==FormWindowState.Minimized)Hide();};
  FormClosing+=delegate(object sender,FormClosingEventArgs e){if(!allowClose && e.CloseReason==CloseReason.UserClosing){e.Cancel=true;Hide();}};
  FormClosed+=delegate{refreshTimer.Stop();refreshTimer.Dispose();if(statusWorker!=null)statusWorker.Dispose();tray.Visible=false;tray.Dispose();if(statusIcon!=null)statusIcon.Dispose();originalIcon.Dispose();};
  refreshTimer.Tick+=delegate{CheckStatus();};refreshTimer.Start();
 }
 void OpenStatus(){Show();WindowState=FormWindowState.Normal;ShowInTaskbar=true;Activate();}
 void ConfirmStop(){if(actionHook!=null || MessageBox.Show(this,"Stop this bridge and its owned WIRES-X session?", "Stop bridge",MessageBoxButtons.YesNo,MessageBoxIcon.Question)==DialogResult.Yes)Action("Stop");}
 void ExitStatus(){
  if(stop.Enabled && actionHook==null && MessageBox.Show(this,"Exit only the status app? The bridge will KEEP RUNNING. Use Stop bridge first if you want to shut it down.","Exit status app",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
  allowClose=true;Close();
 }
 void SetPresentation(string code,string message){
  headline.Text=code=="OtherSession"?"Other session":code=="SetupRequired"?"Setup required":code=="NeedsAttention"?"Needs attention":code;
  summary.Text=message;Text="WiresX 2 YSF Bridge - "+headline.Text;
  Color color=code=="Running"?Color.ForestGreen:(code=="Error" || code=="NeedsAttention")?Color.Firebrick:(code=="Starting" || code=="Connecting" || code=="Degraded")?Color.DarkOrange:Color.DimGray;headline.ForeColor=color;
  tray.Text=("WiresX 2 YSF Bridge - "+headline.Text).Substring(0,Math.Min(63,("WiresX 2 YSF Bridge - "+headline.Text).Length));
  if(iconCode!=code){
   using(var bitmap=new Bitmap(32,32)){using(var g=Graphics.FromImage(bitmap)){g.DrawIcon(originalIcon,new Rectangle(0,0,32,32));using(var border=new SolidBrush(Color.White))g.FillEllipse(border,18,18,14,14);using(var brush=new SolidBrush(color))g.FillEllipse(brush,20,20,10,10);}
    IntPtr handle=bitmap.GetHicon();Icon next;try{next=(Icon)System.Drawing.Icon.FromHandle(handle).Clone();}finally{DestroyIcon(handle);}var old=statusIcon;statusIcon=next;Icon=next;tray.Icon=next;if(old!=null)old.Dispose();
   }iconCode=code;
  }
 }
 static string Value(Dictionary<string,object> data,string name){object value;return data.TryGetValue(name,out value)?Convert.ToString(value):"";}
 static bool Flag(Dictionary<string,object> data,string name){object value;return data.TryGetValue(name,out value) && Object.Equals(value,true);}
 static Dictionary<string,object> Parse(string text){string[] lines=text.Trim().Split('\n');var value=new JavaScriptSerializer().DeserializeObject(lines[lines.Length-1]) as Dictionary<string,object>;if(value==null)throw new Exception("Status response unavailable");return value;}
 string RunStatusScript(string name,string arguments){
  string script=Path.Combine(root,name);if(!File.Exists(script))throw new FileNotFoundException("Application component not installed",script);
  var text=new StringBuilder();using(var p=new Process()){
   p.StartInfo=new ProcessStartInfo("powershell.exe","-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+script+"\" "+arguments) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
   DataReceivedEventHandler append=delegate(object source,DataReceivedEventArgs row){if(row.Data!=null)lock(text){if(text.Length<64000)text.AppendLine(row.Data);}};p.OutputDataReceived+=append;p.ErrorDataReceived+=append;p.Start();p.BeginOutputReadLine();p.BeginErrorReadLine();
   if(!p.WaitForExit(25000)){if(name=="BridgeStatus.ps1")p.Kill();throw new TimeoutException("Operation is still pending; refresh status before retrying.");}p.WaitForExit();return text.ToString();
  }
 }
 void Action(string action){try{
  lastActionError=null;if(action=="Start")pendingStartUntil=DateTime.UtcNow.AddSeconds(30);
  if(actionHook!=null)actionHook(action);
  else{
   string script=Path.Combine(root,"BridgeSupervisor.ps1");if(!File.Exists(script))throw new FileNotFoundException("Launcher backend not installed",script);
   var process=new Process {StartInfo=new ProcessStartInfo("powershell.exe","-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+script+"\" -"+action+(action=="Start"?" -UntilStopped":"")) {UseShellExecute=true,WindowStyle=ProcessWindowStyle.Hidden,WorkingDirectory=root},EnableRaisingEvents=true};
   process.Exited+=delegate{int code=process.ExitCode;process.Dispose();if(code!=0 && !IsDisposed && IsHandleCreated)BeginInvoke(new Action(delegate{lastActionError="The bridge controller reported a fault. Check diagnostics before retrying.";pendingStartUntil=DateTime.MinValue;CheckStatus();}));};process.Start();
  }
  SetPresentation(action=="Start"?"Starting":"Stopping",action=="Start"?"Start requested. Preparing adapter, then launching WIRES-X. Login can take several minutes.":"Stop requested. Waiting for owned resources to clean up.");
  start.Enabled=false;stop.Enabled=false;startItem.Enabled=false;stopItem.Enabled=false;
 }catch(Exception e){pendingStartUntil=DateTime.MinValue;SetPresentation("Error",e.Message);if(actionHook==null)OpenStatus();}}
 void CheckStatus(){
  if(busy || changingStartup || IsDisposed)return;busy=true;check.Enabled=false;var worker=new BackgroundWorker();
  worker.DoWork+=delegate(object sender,DoWorkEventArgs e){e.Result=statusProvider!=null?statusProvider():statusWorker.Read();};
  worker.RunWorkerCompleted+=delegate(object sender,RunWorkerCompletedEventArgs e){busy=false;if(!IsDisposed){
   check.Enabled=true;
   try{
    if(e.Error!=null)throw e.Error;var response=Parse(Convert.ToString(e.Result));if(!response.ContainsKey("Event") || !Object.Equals(response["Event"],"Check"))throw new Exception("Invalid status response");var data=(Dictionary<string,object>)response["Data"];
    string code=Value(data,"StatusCode"),message=Value(data,"Summary");bool canStart=Flag(data,"CanStart"),canStop=Flag(data,"CanStop");
    if(code=="Stopped" && pendingStartUntil>DateTime.UtcNow){code="Starting";message="Start requested. Waiting for the bridge controller.";canStart=false;}
    else if(code!="Stopped")pendingStartUntil=DateTime.MinValue;
    if(lastActionError!=null && (code=="Stopped" || code=="Error")){code="Error";message=lastActionError;}
    SetPresentation(code,message);start.Enabled=canStart;stop.Enabled=canStop;startItem.Enabled=canStart;stopItem.Enabled=canStop;
    string room=Value(data,"NativeRoom");output.Text="WIRES-X room: "+(room.Length>0?room:"Not connected / not verified")+"\r\nYSF destination: "+Value(data,"YsfDestination")+"\r\nStatus checked: "+DateTime.Now.ToString("HH:mm:ss")+"\r\n\r\n"+message;
    applyingStatus=true;startupBox.Checked=Flag(data,"StartupEnabled");applyingStatus=false;startupBox.Enabled=!changingStartup && Value(data,"StartupState")!="Error";startupInfo.Text=Value(data,"StartupMessage")+"\r\nRequires a signed-in desktop; no Windows automatic sign-in is configured.";
    if(autoPending){autoPending=false;if(canStart && Flag(data,"StartupEnabled") && Value(data,"StartupState")=="Enabled")Action("Start");else if(code!="Running" && code!="Starting" && code!="Connecting")OpenStatus();}
   }catch(Exception error){applyingStatus=false;start.Enabled=false;stop.Enabled=false;startItem.Enabled=false;stopItem.Enabled=false;startupBox.Enabled=false;SetPresentation("Error",error.Message);if(autoPending){autoPending=false;OpenStatus();}}
  }worker.Dispose();};worker.RunWorkerAsync();
 }
 void ChangeStartup(){
  bool enable=startupBox.Checked;
  if(startupHook==null && MessageBox.Show(this,enable?"Start this bridge at Windows sign-in, then let it launch WIRES-X? Existing WIRES-X/YMLAN startup shortcuts will be backed up and disabled to prevent a startup race. This does not start the bridge now or configure Windows automatic sign-in.":"Disable automatic bridge startup and restore its original WIRES-X/YMLAN startup shortcuts? The currently running bridge will not be stopped.","Windows sign-in startup",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes){applyingStatus=true;startupBox.Checked=!enable;applyingStatus=false;return;}
  changingStartup=true;startupBox.Enabled=false;startupInfo.Text="Updating sign-in startup settings...";var worker=new BackgroundWorker();
  worker.DoWork+=delegate(object sender,DoWorkEventArgs e){string action=enable?"Enable":"Disable";e.Result=startupHook!=null?startupHook(action):RunStatusScript("StartupIntegration.ps1","-Action "+action);};
  worker.RunWorkerCompleted+=delegate(object sender,RunWorkerCompletedEventArgs e){changingStartup=false;if(!IsDisposed){try{if(e.Error!=null)throw e.Error;var data=Parse(Convert.ToString(e.Result));if(Flag(data,"Enabled")!=enable || Value(data,"State")=="Error")throw new Exception(Value(data,"Message"));startupInfo.Text=Value(data,"Message");}catch(Exception error){startupInfo.Text=error.Message;if(startupHook==null)MessageBox.Show(this,error.Message,"Startup setting needs attention",MessageBoxButtons.OK,MessageBoxIcon.Warning);}CheckStatus();}worker.Dispose();};worker.RunWorkerAsync();
 }
}

// A single private, read-only helper per launcher. Every CHECK repeats all checks.
sealed class BridgeStatusWorker:IDisposable {
 readonly string root;readonly int timeout;readonly object gate=new object();
 Process process;volatile bool disposed;
 public BridgeStatusWorker(string root,int timeout){this.root=Path.GetFullPath(root);this.timeout=timeout;}
 static void Release(Process p){
  if(p==null)return;
  try{p.StandardInput.Close();if(!p.WaitForExit(1000)){p.Kill();p.WaitForExit(3000);}}catch(InvalidOperationException){}catch(System.ComponentModel.Win32Exception){}finally{p.Dispose();}
 }
 public string Read(){lock(gate){
  if(disposed)throw new ObjectDisposedException("BridgeStatusWorker");
  Process p=process;
  try{
   if(p==null){
    string script=Path.Combine(root,"BridgeStatus.ps1");if(!File.Exists(script))throw new FileNotFoundException("Status component not installed",script);
    p=new Process();p.StartInfo=new ProcessStartInfo("powershell.exe","-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+script+"\" -Watch") {UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8};
    // Drain stderr without retaining station data or allowing a full pipe to stall.
    p.ErrorDataReceived+=delegate{};p.Start();p.BeginErrorReadLine();process=p;
    if(disposed)throw new ObjectDisposedException("BridgeStatusWorker");
   }
   p.StandardInput.WriteLine("CHECK");p.StandardInput.Flush();
   var read=p.StandardOutput.ReadLineAsync();if(!read.Wait(timeout))throw new TimeoutException("Status helper timed out; bridge operation is unchanged.");
   if(read.Result==null)throw new IOException("Status helper exited; refresh to retry.");
   return read.Result;
  }catch{if(Object.ReferenceEquals(process,p))process=null;Release(p);throw;}
 }}
 public void Dispose(){disposed=true;Release(System.Threading.Interlocked.Exchange(ref process,null));}
}
