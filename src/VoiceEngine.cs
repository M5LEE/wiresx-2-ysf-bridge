// Copyright (c) 2026 M5LEE. MIT; see LICENSE.
using System;
using System.Collections.Generic;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
namespace CumbriaCQ.Offline {
 public sealed class ConfigurationResetGuard {
  readonly Queue<long> resets=new Queue<long>();long last=-1;
  public bool Allow(long now){
   if(now<0 || now<last)throw new ArgumentException("Monotonic configuration time");last=now;
   while(resets.Count>0 && now-resets.Peek()>=60000)resets.Dequeue();
   if(resets.Count>=3)return false;resets.Enqueue(now);return true;
  }
 }
 public static class RoomLog {
  public static string CurrentRoom(string text){return Connection(text)[0];}
  public static string ConnectionKey(string text){return Connection(text)[1];}
  static string[] Connection(string text){
   string room=null,key=null;
   if(text==null)return new string[]{room,key};
   foreach(string line in text.Split('\n')){
    var row=System.Text.RegularExpressions.Regex.Match(line,@"\A([0-9]{4}/[0-9]{2}/[0-9]{2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2})\s+(.+)");
    if(!row.Success)continue;string message=row.Groups[2].Value.TrimEnd();
    var joined=System.Text.RegularExpressions.Regex.Match(message,@"\AConnected to .+?\(([0-9]{5})\)\.?\z",System.Text.RegularExpressions.RegexOptions.IgnoreCase);
    if(joined.Success){room=joined.Groups[1].Value;key=row.Groups[1].Value+"|"+room;if(room=="00000"){room=null;key=null;}}
    else if(System.Text.RegularExpressions.Regex.IsMatch(message,@"\A(?:Transceiver TX Stop\. Disconnect\.|Disconnect\b|Disconnected\b|return to room\b|Connecting(?:\(|\b))",System.Text.RegularExpressions.RegexOptions.IgnoreCase)){room=null;key=null;}
   }
   return new string[]{room,key};
  }
  public static bool IsConnected(string text,string room){
   string connected=CurrentRoom(text);return connected!=null && (room==null || connected==room);
  }
 }
 public static class NodeRoom {
  public static bool IsConnected(string frame,string room){
   if(room==null || !System.Text.RegularExpressions.Regex.IsMatch(room,@"\A[0-9]{5}\z") || frame==null || !System.Text.RegularExpressions.Regex.IsMatch(frame,@"\AD1F00FA20011000[ -~]{62}[0-9A-F]{180}\z"))return false;
   byte[] payload=new byte[90];for(int i=0;i<90;i++)payload[i]=Convert.ToByte(frame.Substring(77+i*2,2),16);
   int checksum=0x29;foreach(char c in frame.Substring(7,70))checksum+=c;for(int i=0;i<89;i++)checksum+=payload[i];
   if((byte)checksum!=payload[89] || payload[88]!=3)return false;
   string info=System.Text.Encoding.ASCII.GetString(payload,0,88);
   return info.StartsWith("]A_5") && info.Substring(33,2)=="05" && info.Substring(35,5)==room;
  }
 }
 public sealed class BridgeBatch {
  public readonly List<string> Serial=new List<string>();
  public readonly List<byte[]> Network=new List<byte[]>();
 }
 public sealed class VoiceEngine {
  readonly Dictionary<string,int> diagnostics=new Dictionary<string,int>();
  public const int OutboundQueueLimit=8;
  public Dictionary<string,int> DiagnosticCounts { get {var copy=new Dictionary<string,int>(diagnostics);copy["transmit-queue-depth"]=pending.Count;copy["transmit-queue-limit"]=OutboundQueueLimit;return copy;} }
  void Count(string reason){int value;diagnostics.TryGetValue(reason,out value);diagnostics[reason]=value+1;}
  public BridgeBatch Stop(long now){
   BridgeBatch b=new BridgeBatch();
   if(outbound)Send(b,YsfWire.Packet(gateway,source,YsfWire.HeaderFrame(source,gateway,dgId,true),sequence,true),now);
   if(outbound || inbound || dataTx)b.Serial.Add(Notice("00"));
   dataReady=false;dataTx=false;dataPhase=0;
   pending.Clear();received.Clear();outbound=false;inbound=false;ending=false;rxEnding=false;synced=false;metadata=null;source=null;metadataAuxiliary=null;auxiliary=null;rxSource=null;rxVia=null;
   nativeFrames.Clear();nativeFrameOrder.Clear();
   return b;
  }
  readonly string gateway,idle,status;string receiveRoom,receiveRadioId;readonly int dgId;readonly bool allowZeroDg,measuredFtm100Receive;
  public BridgeBatch SetConnectedRoom(string room,long now){
   // PowerShell binds a null string argument as String.Empty: both mean disconnected.
   if(room==String.Empty)room=null;
   if(room!=null && (!System.Text.RegularExpressions.Regex.IsMatch(room,@"\A[0-9]{5}\z") || room=="00000"))throw new ArgumentException("Connected native room");
   if(room==receiveRoom)return new BridgeBatch();
   BridgeBatch stopped=Stop(now);receiveRoom=room;receiveRadioId=status.Substring(12,5);Count("room-transitions");return stopped;
  }
  readonly Queue<byte[]> pending=new Queue<byte[]>();
  readonly Queue<byte[]> received=new Queue<byte[]>();
  readonly Dictionary<int,string> nativeFrames=new Dictionary<int,string>();
  readonly Queue<int> nativeFrameOrder=new Queue<int>();
  readonly Dictionary<string,long> recent=new Dictionary<string,long>();
  readonly Queue<KeyValuePair<string,long>> recentOrder=new Queue<KeyValuePair<string,long>>();
  string metadata,source;byte[] metadataAuxiliary,auxiliary;long metadataAt,nextDue,lastVoice,lastPlayout;bool outbound,ending;int expected,sequence,fn;
  string rxSource,rxVia;bool inbound,synced,rxEnding;long rxDue,rxLast;int rxCounter,rxExpected=-1;
  long rxHeaderAt;int rxHeaderIndex;
  static readonly string[] ReceiveHeaderSlots={"11","12","21","22","31","32"};
  bool dataReady,dataTx;int dataPhase;long dataAt,dataRelease;
  public BridgeBatch ControlTick(long now){
   BridgeBatch b=new BridgeBatch();
   if(dataTx && (now-dataAt>2500 || (dataPhase==4 && now>=dataRelease))){dataTx=false;dataReady=false;dataPhase=0;b.Serial.Add(Notice("00"));}
   else if(dataTx && dataPhase==1 && now-dataAt>=50){dataPhase=2;b.Serial.Add(Notice("25"));}
   else if(dataTx && dataPhase==2 && now-dataAt>=100){dataPhase=3;b.Serial.Add(Notice("45"));}
   else if(dataReady && !dataTx && now-dataAt>2500)dataReady=false;
   return b;
  }
  public VoiceEngine(string gateway,int dgId,string status,string idle,bool allowZeroDg){
   if(gateway==null || !System.Text.RegularExpressions.Regex.IsMatch(gateway,@"\A[A-Z0-9][A-Z0-9 /-]{0,9}\z") || dgId<0 || dgId>127)throw new ArgumentException("Bridge identity or DG-ID");
   if(status==null || !System.Text.RegularExpressions.Regex.IsMatch(status,@"\AD1C000B0[0-9A-F]{4}[A-Za-z0-9]{5}0\z") || idle==null || !System.Text.RegularExpressions.Regex.IsMatch(idle,@"\AB0[0-9 ]+\z"))throw new ArgumentException("Status/idle fixture");
   this.gateway=gateway;this.dgId=dgId;this.idle=idle;this.status=status;this.allowZeroDg=allowZeroDg;
  }
  public VoiceEngine(string gateway,int dgId,string status,string idle,bool allowZeroDg,bool measuredFtm100Receive):this(gateway,dgId,status,idle,allowZeroDg){
   if(measuredFtm100Receive && status.Substring(10,2)!="05")throw new ArgumentException("FTM-100 measured profile requires its genuine idle mode");
   this.measuredFtm100Receive=measuredFtm100Receive;
  }
  // Explicit experimental addressing contract, not a measured RF receive fixture.
  // It uses only the identity already supplied by the owned emulated-set status.
  // The native client remains responsible for expanded metadata and C20 admission.
  public VoiceEngine(string gateway,int dgId,string status,string idle,bool allowZeroDg,string receiveRoom,string receiveRadioId):this(gateway,dgId,status,idle,allowZeroDg,true){
   if(receiveRoom==null || !System.Text.RegularExpressions.Regex.IsMatch(receiveRoom,@"\A[0-9]{5}\z") || receiveRoom=="00000" || receiveRadioId!=status.Substring(12,5))throw new ArgumentException("Assigned room and owned emulated-radio identity required");
   this.receiveRoom=receiveRoom;this.receiveRadioId=receiveRadioId;
  }
  string Status(string phase){
   if(!measuredFtm100Receive)return status.Substring(0,10)+phase+status.Substring(12);
   string level=(phase=="11" || phase=="31")?"A0":status.Substring(8,2);
   phase=phase=="00"?"05":phase=="11"?"15":phase=="31"?"35":phase;
   return status.Substring(0,8)+level+phase+status.Substring(12);
  }
  string Notice(string phase){return "D1P"+Status(phase).Substring(3);}
  static bool Call(string text){return text!=null && System.Text.RegularExpressions.Regex.IsMatch(text,@"\A[A-Z0-9][A-Z0-9 /-]{0,9}\z");}
  static string Digest(byte[] bytes){using(var sha=System.Security.Cryptography.SHA256.Create())return Convert.ToBase64String(sha.ComputeHash(bytes));}
  void Remember(string key,long now,int ttl){
   long expires=now+ttl;recent[key]=expires;recentOrder.Enqueue(new KeyValuePair<string,long>(key,expires));
   while(recentOrder.Count>128 || (recentOrder.Count>0 && recentOrder.Peek().Value<now)){
    KeyValuePair<string,long> old=recentOrder.Dequeue();long current;if(recent.TryGetValue(old.Key,out current) && current==old.Value)recent.Remove(old.Key);
   }
  }
  bool Seen(string key,long now){long expires;return recent.TryGetValue(key,out expires) && expires>=now;}
  void Send(BridgeBatch b,byte[] packet,long now){Remember("network:"+Digest(packet),now,5000);b.Network.Add(packet);}
  int[] PacketInfo(byte[] packet){
   if(packet==null || packet.Length!=155 || System.Text.Encoding.ASCII.GetString(packet,0,4)!="YSFD")throw new ArgumentException("Packet shape");
   for(int i=4;i<34;i++)if(packet[i]<32 || packet[i]>126)throw new ArgumentException("Packet callsign fields");
   byte[] sync={0xD4,0x71,0xC9,0x63,0x4D};for(int i=0;i<5;i++)if(packet[35+i]!=sync[i])throw new ArgumentException("Packet sync");
   byte[] fich=new byte[25];Array.Copy(packet,40,fich,0,25);int[] info=YsfWire.ReadFich(fich);
   if(info[3]!=2 || (info[4]!=dgId && !(allowZeroDg && info[4]==0)))throw new ArgumentException("Packet mode/DG-ID");
   return info;
  }
  public BridgeBatch OnReflector(byte[] packet,long now){
   BridgeBatch b=new BridgeBatch();int[] info;
   try{info=PacketInfo(packet);}catch(ArgumentException){Count("invalid-packet");return b;}
   string caller=System.Text.Encoding.ASCII.GetString(packet,14,10).TrimEnd(' '),via=System.Text.Encoding.ASCII.GetString(packet,4,10).TrimEnd(' ');
   if(!Call(caller) || !Call(via) || outbound || dataReady || dataTx || (caller==gateway && via==gateway) || Seen("network:"+Digest(packet),now)){Count(caller==gateway && via==gateway?"own-loop":"receive-suppressed");return b;}
   if(info[0]==1 && !inbound){Count("missing-header");return b;}
   if(info[0]==0 && !inbound){
    inbound=true;synced=false;rxEnding=false;rxSource=caller;rxVia=via;rxDue=now+100;rxLast=now;rxCounter=measuredFtm100Receive?5:0;rxExpected=-1;metadata=null;b.Serial.Add(Notice("11"));Count("receive-headers");
   }else if(info[0]==1 && inbound && !rxEnding && caller==rxSource && via==rxVia){
    // Preserve admission/pacing exactly; never silently discard capacity losses.
    if(received.Count>=4){Count("receive-queue-full");return b;}
    int serial=packet[34]>>1;if(rxExpected>=0 && ((serial-rxExpected)&127)>3){Count("sequence-gap");return b;}
    received.Enqueue(YsfWire.ReceiveVoice(packet,dgId,allowZeroDg));rxExpected=(serial+1)&127;rxLast=now;if((packet[34]&1)!=0)rxEnding=true;Count("receive-voice-admitted");
   }else if(info[0]==2 && inbound && caller==rxSource && via==rxVia){
    rxEnding=true;rxLast=now;
   }
   return b;
  }
  public BridgeBatch OnClient(string frame,long now){
   BridgeBatch b=new BridgeBatch();
   string headerSource=TransmitMetadata.SourceForFrame(frame);
   if(frame=="P010000"){b.Serial.Add(inbound?"B1"+idle.Substring(2):idle);if(outbound)ending=true;if(dataTx && dataPhase!=4){dataPhase=4;dataRelease=now+50;b.Serial.Add(Notice("25"));}}
   else if(frame=="P110000" && (dataReady || dataTx)){
    b.Serial.Add(idle);if(!dataTx){dataTx=true;dataAt=now;dataPhase=1;b.Serial.Add(Notice("05"));}
   }
   else if(frame=="P100000"){b.Serial.Add(idle);if(outbound)b.Serial.Add(Notice("45"));}
   else if(frame=="D1C0000"){b.Serial.Add(Status(dataTx?(dataPhase==1?"05":dataPhase==3?"45":"25"):outbound?"45":inbound?(synced?"31":"11"):"00"));}
   else if(NodeDataEcho.ForFrame(frame)!=null){b=Stop(now);dataReady=true;dataAt=now;b.Serial.Add(frame);}
   else if(headerSource!=null){
    if(!inbound){metadata=headerSource;metadataAuxiliary=TransmitMetadata.AuxiliaryForFrame(frame);metadataAt=now;Count(metadataAuxiliary==null?"transmit-auxiliary-unavailable":"transmit-auxiliary-validated");}
    b.Serial.Add("D1F00010");Count("transmit-header-acknowledged");
    Count("transmit-header-acknowledged-"+(frame.Length==115?"extended":"short")+frame.Substring(7,2));
   }else if(frame!=null && frame.StartsWith("D1E")){
    Count("transmit-voice-seen");
    byte[] payload;try{payload=VoiceCodec.ParseVoice(frame);}catch(ArgumentException){Count("transmit-invalid-voice");return b;}
    b.Serial.Add("D1E00010");
    // An arrival must not revive old buffered speech after a real scheduling stall.
    if(outbound && now-lastVoice>400 && now-lastPlayout>400){
     var expired=Stop(now);b.Serial.AddRange(expired.Serial);b.Network.AddRange(expired.Network);Count("transmit-stale-expired");
    }
    if(inbound || dataReady || dataTx || ending){Count("transmit-busy");return b;}
    if(!outbound && (metadata==null || now<metadataAt || now-metadataAt>1000)){Count("transmit-missing-header");return b;}

    if(Seen("receive:"+(outbound?source:metadata)+":"+Digest(payload),now)){Count("transmit-loop");return b;}
    int counter=Convert.ToInt32(frame.Substring(8,4),16);
    string payloadDigest=Digest(payload),seenDigest;
    if(outbound && nativeFrames.TryGetValue(counter,out seenDigest) && seenDigest==payloadDigest){Count("transmit-duplicate");return b;}
    if(!outbound){source=metadata;auxiliary=metadataAuxiliary;outbound=true;expected=counter;sequence=1;fn=0;nextDue=now;lastPlayout=now;Send(b,YsfWire.Packet(gateway,source,YsfWire.HeaderFrame(source,gateway,dgId,false),0,false),now);}
    // A bounded forward loss must not lock out the remainder of an over.
    // Preserve duplicate/backward/misaligned rejection; do not invent audio.
    if(counter!=expected){
     int ahead=(counter-expected)&65535;
     if(ahead>20 || ahead%5!=0){
      Count("transmit-sequence-rejected");Count(ahead>32768?"transmit-sequence-backward":ahead%5!=0?"transmit-sequence-misaligned":"transmit-sequence-large-forward");
      diagnostics["transmit-last-rejected-counter"]=counter;diagnostics["transmit-last-expected-counter"]=expected;return b;
     }
     Count("transmit-sequence-gap");for(int skipped=0;skipped<ahead;skipped+=5)Count("transmit-frames-missing");
    }
    PumpOutbound(b,now);
    // Track validated input even when bounded backpressure drops its payload.
    // Otherwise our own overflow looks like an ever-growing upstream gap.
    expected=(counter+5)&65535;lastVoice=now;
    nativeFrames[counter]=payloadDigest;nativeFrameOrder.Enqueue(counter);while(nativeFrameOrder.Count>16){nativeFrames.Remove(nativeFrameOrder.Dequeue());}
    if(pending.Count>=OutboundQueueLimit){Count("transmit-queue-full");return b;}
    pending.Enqueue((byte[])payload.Clone());Count("transmit-voice-admitted");
    int peak;diagnostics.TryGetValue("transmit-queue-peak",out peak);if(pending.Count>peak)diagnostics["transmit-queue-peak"]=pending.Count;
   }
   return b;
  }
  void PumpOutbound(BridgeBatch b,long now){
   if(outbound && pending.Count>0 && now>=nextDue){
    // Yaesu table 4-4: FN2 is downlink; FN4/5 are ID remarks, not callsigns.
    string data=fn==0?"**********":fn==1?source:fn==2?gateway:"";
    byte[] radio;
    if(fn>=6 && auxiliary!=null){byte[] block=new byte[10];Array.Copy(auxiliary,(fn-6)*10,block,0,10);radio=YsfWire.VoiceDataFrame(pending.Dequeue(),fn,7,dgId,block);Count("transmit-auxiliary-blocks-emitted");}
    else radio=YsfWire.VoiceFrame(pending.Dequeue(),fn,7,dgId,data);
    Send(b,YsfWire.Packet(gateway,source,radio,sequence,false),now);
    Count("transmit-voice-emitted");
    lastPlayout=now;
    sequence=(sequence+1)&127;fn=(fn+1)%8;nextDue+=100;if(nextDue<=now)nextDue=now+100;
   }
  }
  public BridgeBatch Tick(long now){
   BridgeBatch b=ControlTick(now);
   if(inbound && now-rxLast>400){received.Clear();rxEnding=true;rxDue=now;}
   if(inbound && rxEnding && received.Count==0 && now>=rxDue){
    inbound=false;synced=false;rxEnding=false;rxSource=null;rxVia=null;metadata=null;b.Serial.Add(Notice("00"));
   }
   if(inbound && now>=rxDue){
    if(!synced){
     synced=true;b.Serial.Add(Notice("31"));
     string prefix=receiveRoom!=null?"21002000":measuredFtm100Receive?"20002000":"21002000";
     b.Serial.Add("D1H001E"+prefix+"10"+(receiveRoom!=null?receiveRoom+receiveRadioId:"**********")+rxSource.PadRight(10));
     if(receiveRoom==null){
     if(measuredFtm100Receive){rxHeaderAt=now;rxHeaderIndex=0;b.Serial.Add("D1H001E"+prefix+"20"+gateway.PadRight(10)+new string(' ',10));}
     // Synthetic suffix, not a captured GPS/control profile. The native G
     // ingress checks its final decoded byte against the sum of preceding bytes.
     string tail=measuredFtm100Receive?BitConverter.ToString(System.Text.Encoding.ASCII.GetBytes(new string(' ',20))).Replace("-",""):"0C"+new string('0',12);
     int checksum=0;for(int i=0;i<tail.Length-2;i+=2)checksum=(checksum+Convert.ToInt32(tail.Substring(i,2),16))&255;tail=tail.Substring(0,tail.Length-2)+checksum.ToString("X2");
     b.Serial.Add((measuredFtm100Receive?"D1G006C":"D1G0052")+prefix+"**********"+rxSource.PadRight(10)+gateway.PadRight(10)+rxVia.PadRight(10)+new string(' ',20)+tail);
     }
    }
    if(received.Count>0){byte[] payload=received.Dequeue();Remember("receive:"+rxSource+":"+Digest(payload),now,2000);b.Serial.Add(VoiceCodec.SerialVoice("D1R",rxCounter,payload));Count("serial-voice-emitted");rxCounter=(rxCounter+5)&65535;rxDue+=100;if(rxDue<=now)rxDue=now+100;}
   }
   if(inbound && synced && receiveRoom==null && measuredFtm100Receive && rxHeaderIndex<ReceiveHeaderSlots.Length && now-rxHeaderAt>=(rxHeaderIndex+1)*100){
    string slot=ReceiveHeaderSlots[rxHeaderIndex++];
    string first=slot[0]=='1'?"**********":slot[0]=='2'?gateway.PadRight(10):new string(' ',10);
    string second=slot[0]=='1'?rxSource.PadRight(10):new string(' ',10);
    b.Serial.Add("D1H001E20002000"+slot+first+second);
   }
   // Burst arrivals can be quiet while their valid buffered speech is still playing.
   if(outbound && now-lastVoice>400 && now-lastPlayout>400){pending.Clear();ending=true;}
   PumpOutbound(b,now);
   if(outbound && ending && pending.Count==0){
    Send(b,YsfWire.Packet(gateway,source,YsfWire.HeaderFrame(source,gateway,dgId,true),sequence,true),now);
    outbound=false;ending=false;metadata=null;source=null;metadataAuxiliary=null;auxiliary=null;b.Serial.Add(Notice("00"));
    nativeFrames.Clear();nativeFrameOrder.Clear();
   }
   return b;
  }
 }
 public sealed class NativeLogView { public string Text; public int Lines; public bool Partial; }
 public static class NativeLogTail {
  public delegate bool Child(IntPtr h,IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h,Child f,IntPtr p);
  [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
  [DllImport("user32.dll",EntryPoint="GetWindowLongW")] static extern int GetWindowLong(IntPtr h,int index);
  [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="SendMessageTimeoutW")] static extern IntPtr Send(IntPtr h,uint message,UIntPtr w,IntPtr l,uint flags,uint ms,out UIntPtr result);
  static int Query(IntPtr h,uint message,int w,IntPtr data){UIntPtr result;if(Send(h,message,new UIntPtr((uint)w),data,2,100,out result)==IntPtr.Zero)throw new InvalidOperationException("ReadTimeout");long n=(long)result.ToUInt64();if(n<0||n>1000000)throw new InvalidOperationException("ReadRange");return (int)n;}
  public static NativeLogView ReadNative(IntPtr main){
   if(main==IntPtr.Zero)throw new ArgumentException("MissingWindow");IntPtr log=IntPtr.Zero;
   EnumChildWindows(main,delegate(IntPtr h,IntPtr p){if(GetDlgCtrlID(h)==1014){var name=new StringBuilder(64);GetClassName(h,name,64);if(name.ToString()=="Edit" && (GetWindowLong(h,-16)&32)==0)log=h;}return true;},IntPtr.Zero);
   if(log==IntPtr.Zero)throw new InvalidOperationException("DiagnosticControlUnavailable");return ReadEdit(log);
  }
  public static NativeLogView ReadEdit(IntPtr edit){
   int total=Query(edit,0xBA,0,IntPtr.Zero),first=Math.Max(0,total-256);var text=new StringBuilder();var clock=Stopwatch.StartNew();var view=new NativeLogView();
   IntPtr buffer=Marshal.AllocHGlobal(2048);
   try{for(int line=first;line<total;line++){
     if(clock.ElapsedMilliseconds>=1500){view.Partial=true;break;}
     Marshal.WriteInt16(buffer,1023);int n=Query(edit,0xC4,line,buffer);if(n>1023)throw new InvalidOperationException("LineRange");
     if(n==1023)view.Partial=true;text.Append(Marshal.PtrToStringUni(buffer,n));text.Append('\n');view.Lines++;
    }}finally{Marshal.FreeHGlobal(buffer);}
   view.Text=text.ToString();return view;
  }
 }
}
