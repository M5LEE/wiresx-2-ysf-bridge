// Copyright (c) 2026 M5LEE.
// SPDX-License-Identifier: GPL-3.0-or-later
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
 readonly Label headline=new Label(),summary=new Label(),nextSteps=new Label();
 readonly TextBox output=new TextBox();
 readonly Button setup=new Button(),check=new Button(),start=new Button(),stop=new Button(),recover=new Button();
 readonly CheckBox startupBox=new CheckBox();
 readonly Label startupInfo=new Label();
 readonly NotifyIcon tray=new NotifyIcon();
 readonly ToolStripMenuItem openItem=new ToolStripMenuItem("Open status"),startItem=new ToolStripMenuItem("Start bridge"),stopItem=new ToolStripMenuItem("Stop bridge"),exitItem=new ToolStripMenuItem("Exit status app (bridge stays running)");
 readonly Timer refreshTimer=new Timer {Interval=5000};
 readonly Icon originalIcon;
 Icon statusIcon;
 string iconCode,lastActionError;
 bool busy,changingStartup,applyingStatus,autoPending,allowClose,autoRecoveryPending,autoRecoveryAttempted,needFreshCheck;
 DateTime pendingStartUntil=DateTime.MinValue;
 [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr handle);
 public LauncherForm(string root):this(root,false,null,null,null){}
 public LauncherForm(string root,bool autoStart,Func<string> readStatus,Action<string> actionHook,Func<string,string> startupHook){
  this.root=Path.GetFullPath(root);statusProvider=readStatus;this.actionHook=actionHook;this.startupHook=startupHook;autoPending=autoStart;
  if(readStatus==null)statusWorker=new BridgeStatusWorker(this.root,25000);
  originalIcon=new Icon(Path.Combine(root,"assets","bridge.ico"));Icon=(Icon)originalIcon.Clone();
  Text="WiresX 2 YSF Bridge - Checking";Font=new Font("Segoe UI",10F);StartPosition=FormStartPosition.CenterScreen;ClientSize=new Size(720,550);MinimumSize=new Size(736,589);AutoScaleMode=AutoScaleMode.Dpi;
  var layout=new TableLayoutPanel {Dock=DockStyle.Fill,Padding=new Padding(16),ColumnCount=1,RowCount=8};Controls.Add(layout);
  foreach(float height in new float[]{44,54,96,132,66,42,32,40})layout.RowStyles.Add(new RowStyle(SizeType.Absolute,height));
  headline.Text="Checking";headline.Name="BridgeStatus";headline.AccessibleName="Bridge status";headline.Font=new Font(Font.FontFamily,21F,FontStyle.Bold);headline.Dock=DockStyle.Fill;layout.Controls.Add(headline,0,0);
  summary.Text="Reading bridge status...";summary.Dock=DockStyle.Fill;layout.Controls.Add(summary,0,1);
  nextSteps.Dock=DockStyle.Fill;nextSteps.Padding=new Padding(8);nextSteps.BackColor=Color.AliceBlue;nextSteps.Font=new Font(Font.FontFamily,9F);nextSteps.AccessibleName="What to do next";nextSteps.Text="What to do next\r\nPlease wait for the status check.";layout.Controls.Add(nextSteps,0,2);
  var steps=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2,RowCount=3};steps.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,205));steps.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));layout.Controls.Add(steps,0,3);
  Button[] ordered={setup,check,start};string[] titles={"1. Set up bridge","2. Check status","3. Start bridge"};string[] hints={"Choose your YSF callsign and room. Usually needed only once.","Check readiness. Read the recommended fix above if something is missing.","Launch the bridge and WIRES-X. No need to open WIRES-X separately."};
  for(int i=0;i<ordered.Length;i++){steps.RowStyles.Add(new RowStyle(SizeType.Absolute,44));ordered[i].Text=titles[i];ordered[i].Dock=DockStyle.Fill;ordered[i].Margin=new Padding(3,5,8,5);steps.Controls.Add(ordered[i],0,i);steps.Controls.Add(new Label {Text=hints[i],Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleLeft,Font=new Font(Font.FontFamily,9F)},1,i);}start.Enabled=false;
  output.Multiline=true;output.ReadOnly=true;output.ScrollBars=ScrollBars.Vertical;output.Dock=DockStyle.Fill;output.AccessibleName="Bridge connection details";output.BackColor=SystemColors.Window;layout.Controls.Add(output,0,4);
  var buttons=new FlowLayoutPanel {Dock=DockStyle.Fill,WrapContents=false};stop.Text="Stop bridge";stop.AutoSize=true;stop.Enabled=false;recover.Text="Recover session";recover.AutoSize=true;recover.Visible=false;recover.Enabled=false;var config=new Button {Text="Change YSF room",AutoSize=true};buttons.Controls.AddRange(new Control[]{recover,stop,config});layout.Controls.Add(buttons,0,5);
  startupBox.Text="Start automatically when I sign in to Windows";startupBox.AutoSize=true;startupBox.Dock=DockStyle.Fill;startupBox.Enabled=false;layout.Controls.Add(startupBox,0,6);
  startupInfo.Dock=DockStyle.Fill;startupInfo.ForeColor=Color.DimGray;startupInfo.Text="Sign-in startup is optional. Windows automatic sign-in is never configured.";layout.Controls.Add(startupInfo,0,7);
  recover.Click+=delegate{if(actionHook!=null || MessageBox.Show(this,"Recover an interrupted session? Close WIRES-X and YMLAN first. Recovery verifies that the old bridge is stopped, restores only its two saved port names and keeps your setup. It will not start anything.","Recover session",MessageBoxButtons.YesNo,MessageBoxIcon.Information)==DialogResult.Yes)Action("Recover");};
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
  summary.Text=message;nextSteps.Text="What to do next\r\n"+RecommendedSteps(code);Text="WiresX 2 YSF Bridge - "+headline.Text;
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
   // Controller lifetime must not depend on this UI or redirected UI-owned pipes.
   var process=new Process {StartInfo=new ProcessStartInfo("powershell.exe","-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+script+"\" -"+action+(action=="Start"?" -UntilStopped":"")) {UseShellExecute=true,WindowStyle=ProcessWindowStyle.Hidden,WorkingDirectory=root},EnableRaisingEvents=true};
   process.Exited+=delegate{int code=process.ExitCode,pid=process.Id;process.Dispose();if(!IsDisposed && IsHandleCreated)BeginInvoke(new Action(delegate{CompleteAction(action,code,code==0?null:ReadActionError(pid));}));};process.Start();
  }
  SetPresentation(action=="Start"?"Starting":action=="Recover"?"Recovering":"Stopping",action=="Start"?"Preparing the bridge, then launching WIRES-X. Login can take several minutes.":action=="Recover"?"Checking the old session and restoring its saved port names. Nothing will be started.":"Stopping the bridge and restoring its connections. Please wait.");
  start.Enabled=false;stop.Enabled=false;recover.Enabled=false;startItem.Enabled=false;stopItem.Enabled=false;
 }catch(Exception e){autoRecoveryPending=false;autoPending=false;pendingStartUntil=DateTime.MinValue;SetPresentation("Error",e.Message);if(actionHook==null)OpenStatus();}}
 void CompleteAction(string action,int code,string error){
  lastActionError=code==0?null:ExplainActionError(error);pendingStartUntil=DateTime.MinValue;
  if(action=="Recover" && autoRecoveryPending){autoRecoveryPending=false;autoPending=code==0;if(code!=0)OpenStatus();}
  // Discard any status query started before the recovery process released its lock.
  if(busy)needFreshCheck=true;else CheckStatus();
 }
 void CheckStatus(){
  if(busy || changingStartup || IsDisposed)return;busy=true;check.Enabled=false;var worker=new BackgroundWorker();
  worker.DoWork+=delegate(object sender,DoWorkEventArgs e){e.Result=statusProvider!=null?statusProvider():statusWorker.Read();};
  worker.RunWorkerCompleted+=delegate(object sender,RunWorkerCompletedEventArgs e){busy=false;if(!IsDisposed){
   if(needFreshCheck){needFreshCheck=false;worker.Dispose();CheckStatus();return;}
   check.Enabled=true;
   try{
    if(e.Error!=null)throw e.Error;var response=Parse(Convert.ToString(e.Result));if(!response.ContainsKey("Event") || !Object.Equals(response["Event"],"Check"))throw new Exception("Invalid status response");var data=(Dictionary<string,object>)response["Data"];
    string code=Value(data,"StatusCode"),message=Value(data,"Summary");bool canStart=Flag(data,"CanStart"),canStop=Flag(data,"CanStop");
    if(code=="Stopped" && pendingStartUntil>DateTime.UtcNow){code="Starting";message="Start requested. Waiting for the bridge controller.";canStart=false;}
    else if(code!="Stopped")pendingStartUntil=DateTime.MinValue;
    if(lastActionError!=null && (code=="Stopped" || code=="Error" || code=="NeedsAttention")){code="Error";message=lastActionError;}
    SetPresentation(code,message);if(lastActionError==null && Value(data,"NextStep").Length>0)nextSteps.Text="What to do next\r\n"+Value(data,"NextStep");start.Enabled=canStart;stop.Enabled=canStop;startItem.Enabled=canStart;stopItem.Enabled=canStop;
    recover.Visible=Flag(data,"CanRecover");recover.Enabled=Flag(data,"CanRecover") && !autoRecoveryPending;
    string room=Value(data,"NativeRoom");output.Text="WIRES-X room: "+(room.Length>0?room:"Not connected")+"\r\nYSF room: "+Value(data,"YsfDestination")+"\r\nChecked: "+DateTime.Now.ToString("HH:mm:ss");
    applyingStatus=true;startupBox.Checked=Flag(data,"StartupEnabled");applyingStatus=false;startupBox.Enabled=!changingStartup && Value(data,"StartupState")!="Error";startupInfo.Text=Value(data,"StartupMessage");
    if(autoPending){
     autoPending=false;bool armed=Flag(data,"StartupEnabled") && Value(data,"StartupState")=="Enabled";
     if(canStart && armed)Action("Start");
     else if(armed && code=="NeedsAttention" && Flag(data,"CanRecover") && !autoRecoveryAttempted){
      autoRecoveryAttempted=true;autoRecoveryPending=true;Action("Recover");
     }else if(code!="Running" && code!="Starting" && code!="Connecting")OpenStatus();
    }
   }catch(Exception error){applyingStatus=false;start.Enabled=false;stop.Enabled=false;recover.Enabled=false;startItem.Enabled=false;stopItem.Enabled=false;startupBox.Enabled=false;SetPresentation("Error",error.Message);if(autoPending){autoPending=false;OpenStatus();}}
  }worker.Dispose();};worker.RunWorkerAsync();
 }
 static string ReadActionError(int pid){
  try{string path=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"M5LEE","WIRESX-to-YSF-Brtidge","last-controller-error.json");if(new FileInfo(path).Length>65536)return "UnknownControllerError";var data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(path));DateTime stamp=DateTime.Parse(Value(data,"Utc")).ToUniversalTime();if(Convert.ToInt32(data["Pid"])==pid && stamp<=DateTime.UtcNow.AddSeconds(2) && stamp>=DateTime.UtcNow.AddMinutes(-2))return Value(data,"Code");}catch{}return "UnknownControllerError";
 }
 static string RecommendedSteps(string code){
  switch(code){
   case "NeedsAttention":return "Close WIRES-X and YMLAN first. Click Recover session below, then 2. Check status.\r\nWhen ready, click 3. Start bridge. Your saved setup is kept.";
   case "SetupRequired":return "Click 1. Set up bridge. Enter your YSF callsign and select a room.\r\nComplete the connection tools if requested, then return to 2. Check status.";
   case "Stopped":return "Already set up? Click 3. Start bridge.\r\nFirst time here? Follow buttons 1, 2 and 3 from top to bottom.";
   case "Starting":case "Connecting":return "Allow several minutes for WIRES-X to log in. Do not keep pressing Start.\r\nIf it stays here, check the WIRES-X window for a login/room error and check your Internet connection.";
   case "Degraded":return "Click 2. Check status again. Check Internet access and the selected YSF room.\r\nDo not reinstall or change settings just because a status update is late.";
   case "OtherSession":return "Use the status window belonging to the running bridge.\r\nIf changing installations, stop that bridge normally first. Do not force-close its processes.";
   case "Running":return "No action needed. The bridge is ready to use.\r\nClosing this window leaves the bridge running. Use Stop bridge to shut it down.";
   case "Recovering":case "Stopping":return "Please wait for this operation to finish, then click 2. Check status.\r\nDo not run a second recovery or start another bridge.";
   case "Error":return "Follow the message above, then click 2. Check status once.\r\nIf status will not load, reopen only this status app as administrator.\r\nIf a component is missing, repair the installation without deleting your saved station data.";
   default:return "Please wait for the status check. Nothing is started by checking status.";
  }
 }
 static string ExplainActionError(string code){
  switch(code){
   case "CloseWiresXBeforeRecovery":return "Close WIRES-X and YMLAN, then select Recover session again. Nothing has been changed.";
   case "ExistingOwnerRequiresInspection":case "SupervisorNotAliveManualRecoveryRequired":return "The previous session did not finish cleanup. Close WIRES-X, then select Recover session. Do not delete your setup.";
   case "ExistingAdapter":case "RecoverySessionStillAlive":return "A bridge process is still running. Recovery was refused; stop that session normally first.";
   case "CaptureYourOwnRadioProfileFirst":return "Open Setup > Advanced setup and create or import your own connection profile. Your WIRES-X login does not need changing.";
   case "RecoveryAliasChanged":case "RecoveryAliasScope":case "InvalidRecoveryOwner":return "The saved connections do not match this session. No automatic recovery is safe. Keep your settings and ask for support. Code: "+code;
   case "InstalledBinaryHashMismatch":return "An installed component does not match its manifest. Repair the installation; keep your station data.";
   case "AdapterReadyTimeout":case "AdapterExitedBeforeReady":return "The adapter could not open its connections. Check the HRI-200 USB connection and the ports in Setup > Advanced setup.";
   default:return "The operation failed. Your saved setup has been kept. Error code: "+code+". Refresh status before retrying.";
  }
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
