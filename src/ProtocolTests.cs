using System;
using System.Collections.Generic;
using System.Text;
using CumbriaCQ.Offline;
class Program {
 static int total;
 static void Check(bool condition,string name){if(!condition)throw new Exception("FAIL: "+name);total++;Console.WriteLine("PASS: "+name);}
 static void ParserTests(){
  FrameParser p=new FrameParser(256);
  Check(p.Feed(Encoding.ASCII.GetBytes("noise\x01M")).Count==0,"fragment remains buffered");
  List<string> got=p.Feed(new byte[]{48,48,4,1,80,48,49,48,48,48,48,4});
  Check(got.Count==2 && got[0]=="M00" && got[1]=="P010000","fragmented and coalesced serial frames");
  got=p.Feed(new byte[]{1,65,1,66,4});
  Check(got.Count==1 && got[0]=="B","nested start resynchronizes");
  byte[] over=new byte[300];for(int i=0;i<over.Length;i++)over[i]=65;over[0]=1;over[299]=4;
  Check(p.Feed(over).Count==0,"oversized serial frame discarded");
  Check(p.Feed(new byte[]{1,65,0,66,4}).Count==0,"non printable serial payload rejected");
  Check(p.Feed(new byte[]{1,77,48,48,4})[0]=="M00","parser recovers after rejected input");
 }
 static void Reject(Action action,string name){bool rejected=false;try{action();}catch(ArgumentException){rejected=true;}Check(rejected,name);}
 static void VoiceTests(){
  byte[] voice=new byte[65];for(int i=0;i<65;i++)voice[i]=(byte)(i*3);
  string d1e=VoiceCodec.SerialVoice("D1E",65535,voice);
  Check(d1e.Length==144 && d1e.StartsWith("D1E00892FFFF00"),"D1E wire layout matches published format");
  byte[] decoded=VoiceCodec.ParseVoice(d1e);
  Check(BitConverter.ToString(decoded)==BitConverter.ToString(voice),"D1E voice round trip is byte exact");
  Check(VoiceCodec.SerialVoice("D1R",65536,voice).StartsWith("D1R00892000000"),"serial counter wraps at 16 bits");
  Reject(delegate{VoiceCodec.ParseVoice(d1e.Substring(0,143));},"truncated voice rejected");
  Reject(delegate{VoiceCodec.ParseVoice("D1X"+d1e.Substring(3));},"unknown voice direction rejected");
  Reject(delegate{VoiceCodec.ParseVoice(d1e.Substring(0,143)+"Z");},"non hex voice rejected");
  Reject(delegate{VoiceCodec.SerialVoice("D1E",0,new byte[64]);},"wrong payload length rejected");
  byte[] template=new byte[155];for(int i=0;i<155;i++)template[i]=(byte)i;
  Array.Copy(Encoding.ASCII.GetBytes("YSFD"),template,4);
  byte[] original=(byte[])template.Clone();
  byte[] packet=VoiceCodec.PutVoice(template,voice);
  Check(BitConverter.ToString(template)==BitConverter.ToString(original),"template input is immutable");
  Check(BitConverter.ToString(VoiceCodec.GetVoice(packet))==BitConverter.ToString(voice),"YSF voice extraction round trip");
  bool preserved=true;for(int i=0;i<155;i++){bool v=false;for(int n=0;n<5;n++)if(i>=70+n*18 && i<83+n*18)v=true;if(!v && packet[i]!=template[i])preserved=false;}
  Check(preserved,"outer header FICH sync and DCH preserved exactly");
  Reject(delegate{VoiceCodec.GetVoice(new byte[155]);},"non YSFD packet rejected");
  Reject(delegate{VoiceCodec.GetVoice(new byte[154]);},"wrong YSF packet length rejected");
  FrameParser parser=new FrameParser(512);
  string serial="\x01"+d1e+"\x04";
  List<string> frames=parser.Feed(Encoding.ASCII.GetBytes(serial));
  byte[] bridgePacket=VoiceCodec.PutVoice(template,VoiceCodec.ParseVoice(frames[0]));
  string back=VoiceCodec.SerialVoice("D1R",0,VoiceCodec.GetVoice(bridgePacket));
  Check(BitConverter.ToString(VoiceCodec.ParseVoice(back))==BitConverter.ToString(voice),"in memory serial to YSF to serial loopback");
 }
 static void SessionTests(){
  OfflineSession s=new OfflineSession(2,400);
  byte[] v=new byte[65];v[0]=17;
  Check(s.Begin(0),"offline stream begins");
  Check(!s.Begin(1),"overlapping stream refused");
  Check(s.Push(0,v,0),"first synthetic frame accepted");v[0]=99;
  Check(!s.Push(0,v,1),"duplicate frame refused");
  Check(s.Push(5,v,100),"next sequential frame accepted");
  Check(!s.Push(10,v,200),"bounded queue refuses overflow");
  Check(s.Take(200)[0]==17,"queued payload copied not aliased");
  Check(s.Take(200)[0]==99,"queue order maintained");
  Check(s.Take(200)==null,"empty queue nonblocking");
  Check(s.Push(10,v,250),"queue resumes after drain");
  Check(s.Take(651)==null && !s.Active,"stale stream clears pending voice");
  Check(!s.Push(15,v,652),"voice outside active stream refused");
  Check(s.Begin(700),"new stream starts after expiry");
  Check(s.Push(0,v,700),"new stream counter reset");
  s.End();Check(!s.Active && s.Take(701)==null,"explicit end clears buffered voice");
  Reject(delegate{new OfflineSession(0,400);},"invalid queue capacity rejected");
 }
 static void ShadowTests(){
  ShadowRouter router=new ShadowRouter();
  Check(router.Classify("M10")=="hardware-query","observed client M10 routed to genuine hardware");
  Check(router.Classify("M00")=="hardware-query","handshake routed to genuine HRI");
  Check(router.Classify("R6423")=="hardware-query","identity routed to genuine HRI");
  Check(router.Classify("D1V0000")=="missing-radio-fixture","radio identity explicitly unresolved");
  Check(router.Classify("D1C0000")=="missing-radio-fixture","radio status explicitly unresolved");
  Check(router.Classify("P100000")=="blocked","voice PTT never forwarded");
  Check(router.Classify("P110000")=="blocked","data PTT never forwarded");
  Check(router.Classify("D1M0045EXAMPLE")=="blocked","radio tuning never forwarded");
  Check(router.Classify("P010000")=="blocked","unapproved control default blocked");
  Check(router.Classify("unknown")=="blocked","unknown commands fail closed");
  Check(router.Classify(null)=="blocked","null input fails closed");
  byte[] v=new byte[65];string body=VoiceCodec.SerialVoice("D1E",0,v);
  Check(router.Classify(body)=="offline-voice","digital voice diverted from physical radio");
  Check(router.Classify("D1Ebroken")=="blocked","malformed voice not routed");
 }
 static void RadioFixtureTests(){
  string fixture="D1V0030"+new string('X',48); // Synthetic metadata fixture, not a real radio identity.
  RadioIdReply reply=new RadioIdReply(fixture);
  byte[] first=reply.ForQuery("D1V0000");
  Check(Encoding.ASCII.GetString(first)=="\x01"+fixture+"\x04","identification fixture replay is exact");
  first[1]=0;Check(reply.ForQuery("D1V0000")[1]==68,"identification replay returns independent copy");
  Check(reply.ForQuery("R6423")==null,"fixture never substitutes HRI identity");
  Check(reply.ForQuery("D1C0000")==null,"missing status is not invented");
  Reject(delegate{new RadioIdReply(fixture.Substring(0,54));},"truncated radio fixture rejected");
  Reject(delegate{new RadioIdReply("D1R0030"+new string('X',48));},"voice cannot be used as identification fixture");
  Reject(delegate{new RadioIdReply("D1V0030"+new string('X',47)+"\n");},"control bytes in radio fixture rejected");
 }
 static void ConfigurationTests(){
  string block="433.00000+000.00000"+new string('0',13); // Synthetic configuration, not deployed RF settings.
  string query="D1M00457000"+block+block+"F";
  string fixture="D1M00455000"+block+block+"0";
  ConfigurationReply reply=new ConfigurationReply(query,fixture);
  Check(Encoding.ASCII.GetString(reply.ForQuery(query))=="\x01"+fixture+"\x04","measured-shape configuration reply is replayed rather than echoed");
  Reject(delegate{new ConfigurationReply(query,query);},"configuration echo rejected as an unverified reply");
  string node="D1F00FA20011000"+new string(' ',242);
  Check(Encoding.ASCII.GetString(NodeDataEcho.ForFrame(node))=="\x01"+node+"\x04","software-only node metadata echo experiment preserves frame exactly");
  Check(NodeDataEcho.ForFrame("P110000")==null && NodeDataEcho.ForFrame("D1E00892")==null,"node metadata echo cannot acknowledge PTT or voice");
  Check(NodeDataEcho.ForFrame(node.Substring(0,256))==null && NodeDataEcho.ForFrame(node+"F")==null,"node metadata echo rejects incorrect lengths");
  Check(NodeDataEcho.ForFrame(node.Substring(0,256)+"\n")==null && NodeDataEcho.ForFrame(null)==null,"node metadata echo rejects controls and null");
 }
 static void NativeFichTests(){
  string expected="3127C2D8E4CFBE99B13E4B9D72F6464FD52F9A2784C828111C";
  Check(BitConverter.ToString(YsfWire.EncodeFich(1,3,7,50)).Replace("-","")==expected,"native DG-ID 50 FICH matches independent G4KLX reference");
  byte[] fich=new byte[25];for(int i=0;i<25;i++)fich[i]=Convert.ToByte(expected.Substring(i*2,2),16);
  int[] info=YsfWire.ReadFich(fich);
  Check(info.Length==5 && info[0]==1 && info[1]==3 && info[2]==7 && info[3]==2 && info[4]==50,"independent receive FICH validates and identifies V/D mode 2 and DG-ID");
  byte[] silence={0x7b,0xb2,0x8e,0x43,0x36,0xe4,0xa2,0x39,0x78,0x49,0x33,0x68,0x33};
  byte[] voice=new byte[65];for(int i=0;i<5;i++)Array.Copy(silence,0,voice,i*13,13);
  string frame="D471C9634D30D7C2A91FC3AE99115641ED716E644CD52E79B58A08297A07C3F88EF9457BB28E4336E4A23978493368339A6B871AD37BB28E4336E4A2397849336833107BC8FCC67BB28E4336E4A239784933683339A00250FA7BB28E4336E4A2397849336833F7CC02BD3F7BB28E4336E4A2397849336833";
  Check(BitConverter.ToString(YsfWire.VoiceFrame(voice,1,7,50,"M0YSF/BRG ")).Replace("-","")==frame,"complete YSF communications frame matches independent reference");
  string header="D471C9634D0037BAD1C3002D961320003FE3FA000025DE8368000B8ADB18F3F8F86D5853118D9DDF2363C017607F1C88EEA5E07FC3E426FFBAB9A85ABA46921014BE08A52CD3420EDF9C7575A8F77FB81110F2C643D18C3EE89C85DC8F3DEF0E84251E49946425BF00F0570E21E33C1373F60DFBD5890193";
  Check(BitConverter.ToString(YsfWire.HeaderFrame("M0YSF/BRG",50,false)).Replace("-","")==header,"complete YSF header matches independent reference");
  string terminator="D471C9634DC397BA0D3C41CD9523BB4C0FE18C298A65DE0223C3CB8A76E8F3F8F86D5853118D9DDF2363C017607F1C88EEA5E07FC3E426FFBAB9A85ABA46921014BE08A52CD3420EDF9C7575A8F77FB81110F2C643D18C3EE89C85DC8F3DEF0E84251E49946425BF00F0570E21E33C1373F60DFBD5890193";
  Check(BitConverter.ToString(YsfWire.HeaderFrame("M0YSF/BRG",50,true)).Replace("-","")==terminator,"complete YSF terminator matches independent reference");
  byte[] radio=YsfWire.VoiceFrame(voice,1,7,50,"M0YSF/BRG ");
  byte[] packet=YsfWire.Packet("M5LEE/WX","M0YSF/BRG",radio,127,true);
  Check(packet.Length==155 && Encoding.ASCII.GetString(packet,0,4)=="YSFD" && packet[34]==255,"YSFD wrapper carries seven-bit sequence and separate EOT flag");
  Check(Encoding.ASCII.GetString(packet,4,30)=="M5LEE/WX  M0YSF/BRG ALL       ","YSFD wrapper preserves padded gateway source and destination");
  Check(BitConverter.ToString(VoiceCodec.GetVoice(packet))==BitConverter.ToString(voice),"complete generated YSFD frame preserves encoded voice without transcoding");
  Check(BitConverter.ToString(YsfWire.ReceiveVoice(packet,50,false))==BitConverter.ToString(voice),"receive admission validates framing FICH mode and DG-ID before extracting voice");
  Reject(delegate{YsfWire.ReceiveVoice(YsfWire.Packet("M5LEE/WX","M5LEE",YsfWire.HeaderFrame("M5LEE",50,false),0,false),50,false);},"YSF header is never mistaken for voice");
  Reject(delegate{YsfWire.ReceiveVoice(YsfWire.Packet("M5LEE/WX","M5LEE",YsfWire.HeaderFrame("M5LEE",50,true),0,true),50,false);},"YSF terminator is never mistaken for voice");
  Reject(delegate{YsfWire.ReceiveVoice(packet,51,false);},"other nonzero DG-ID rejected");
  byte[] zero=YsfWire.Packet("M5LEE/WX","M5LEE",YsfWire.VoiceFrame(voice,1,7,0,"M5LEE"),1,false);
  Reject(delegate{YsfWire.ReceiveVoice(zero,50,false);},"zero wire DG-ID requires explicit trusted-reflector permission");
  Check(BitConverter.ToString(YsfWire.ReceiveVoice(zero,50,true))==BitConverter.ToString(voice),"explicit trusted-reflector zero-DG-ID policy preserves payload");
  byte[] corrupt=(byte[])packet.Clone();corrupt[40]^=1;
  Reject(delegate{YsfWire.ReceiveVoice(corrupt,50,false);},"corrupted FICH rejected before voice extraction");
  Reject(delegate{YsfWire.ReadFich(new byte[24]);},"truncated FICH rejected");
  Reject(delegate{YsfWire.ReceiveVoice(new byte[154],50,false);},"truncated network frame rejected");
  Reject(delegate{YsfWire.EncodeFich(1,0,7,128);},"invalid DG-ID not silently masked");
  Reject(delegate{YsfWire.VoiceFrame(new byte[64],1,7,50,"M5LEE");},"short encoded voice cannot generate a frame");
  Reject(delegate{YsfWire.HeaderFrame("M5LEE\u00e9",50,false);},"non-ASCII metadata rejected rather than repaired");
  Reject(delegate{YsfWire.Packet("M5LEE/WX","M5LEE",radio,128,false);},"sequence overflow requires explicit wrap by session owner");
 }
 static string VoiceHeader(string source){return "D1F005221016000"+"*****     "+source.PadRight(10)+new string(' ',40)+"09"+new string('0',12);}
 static void RoomGateTests(){
  var dataEngine=new VoiceEngine("TEST1/WX",50,"D1C000B00000TEST10","B0 0    0000000",true);
  dataEngine.OnClient("D1F00FA20011000"+new string(' ',242),0);
  var keyData=dataEngine.OnClient("P110000",1);
  Check(keyData.Serial.Contains("B0 0    0000000") && keyData.Serial.Contains("D1P000B00005TEST10") && keyData.Network.Count==0,"software-only node data key acknowledges without RF or network voice");
  Check(dataEngine.Tick(61).Serial.Contains("D1P000B00025TEST10"),"software node data advances key phase");
  Check(dataEngine.Tick(121).Serial.Contains("D1P000B00045TEST10"),"software node data reaches transmit indication");
  dataEngine.OnClient("P010000",150);
  Check(dataEngine.Tick(211).Serial.Contains("D1P000B00000TEST10"),"software node data unkeys back to idle");
  string log="2026/11/05 23:20:00 Connected to CUMBRIA-CQ(12345).\r\n2026/11/05 23:20:01 Member not message.\r\n";
  Check(RoomLog.IsConnected(log,"12345"),"native diagnostic-log gate recognises an explicit own-room connection");
  Check(!RoomLog.IsConnected(log+"2026/11/05 23:20:02 Transceiver TX Stop. Disconnect.\r\n","12345"),"native log gate revokes forwarding immediately on disconnect");
  Check(!RoomLog.IsConnected(log+"2026/11/05 23:20:03 Connected to OTHER(28054).\r\n","12345"),"native log gate cannot admit another room");
  Check(!RoomLog.IsConnected("Connected to CUMBRIA-CQ(12345).","12345"),"unstructured chat-like text cannot establish room ownership");
  string info="]A_5"+"12345"+"TESTNODE  "+"TESTCITY      "+"05"+"12345"+"CUMBRIA-CQ      "+"002"+new string(' ',29)+"\x03";
  string head="20011000"+new string(' ',60)+"09";byte[] bytes=Encoding.ASCII.GetBytes(info);int checksum=0x29;foreach(char c in head)checksum+=c;foreach(byte v in bytes)checksum+=v;
  string frame="D1F00FA"+head+BitConverter.ToString(bytes).Replace("-","")+((byte)checksum).ToString("X2");
  Check(NodeRoom.IsConnected(frame,"12345"),"live forwarding gate verifies own connected room from node metadata and checksum");
  Check(!NodeRoom.IsConnected(frame,"28054") && !NodeRoom.IsConnected(VoiceHeader("M5LEE"),"12345"),"other rooms and short voice headers cannot open own-room forwarding gate");
  Check(!NodeRoom.IsConnected(frame.Substring(0,256)+(frame[256]=='0'?"1":"0"),"12345"),"corrupted node identification cannot open live forwarding gate");
 }
 static void EngineOutboundTests(){
  var gap=new VoiceEngine("TEST1/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  byte[] tail=new byte[65];for(int i=0;i<tail.Length;i++)tail[i]=0x23;
  gap.OnClient(VoiceHeader("TESTCALL"),0);gap.OnClient(VoiceCodec.SerialVoice("D1E",0,new byte[65]),0);gap.Tick(0);
  gap.OnClient(VoiceCodec.SerialVoice("D1E",10,tail),200);
  var recovered=gap.Tick(200);
  Check(recovered.Network.Count==1 && BitConverter.ToString(YsfWire.ReceiveVoice(recovered.Network[0],50,false))==BitConverter.ToString(tail),"one missing native voice frame cannot suppress the remaining valid over");
  gap.OnClient(VoiceCodec.SerialVoice("D1E",10,tail),210);Check(gap.Tick(210).Network.Count==0,"recovered outbound stream still refuses a duplicate counter");
  gap.OnClient(VoiceCodec.SerialVoice("D1E",16,tail),220);Check(gap.Tick(220).Network.Count==0,"misaligned native voice counters are not accepted as loss recovery");
  gap.OnClient(VoiceCodec.SerialVoice("D1E",15,tail),300);Check(gap.Tick(300).Network.Count==1,"invalid counters cannot poison the next correctly sequenced voice frame");
  var quality=gap.DiagnosticCounts;
  Check(quality.ContainsKey("transmit-voice-seen") && quality["transmit-voice-seen"]==5 && quality["transmit-voice-admitted"]==3 && quality["transmit-voice-emitted"]==3 && quality["transmit-sequence-rejected"]==2 && quality["transmit-sequence-gap"]==1 && quality["transmit-frames-missing"]==1,"outbound quality counters distinguish admitted emitted rejected and missing frames without retaining voice");
  var burst=new VoiceEngine("TEST1/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);burst.OnClient(VoiceHeader("BURST"),0);
  for(int i=0;i<5;i++)burst.OnClient(VoiceCodec.SerialVoice("D1E",i*5,new byte[65]),0);
  for(int i=0;i<4;i++)burst.Tick(i*100);
  burst.OnClient(VoiceCodec.SerialVoice("D1E",25,tail),400);var burstTail=burst.Tick(400);
  Check(burstTail.Network.Count==1 && BitConverter.ToString(YsfWire.ReceiveVoice(burstTail.Network[0],50,false))==BitConverter.ToString(tail),"bounded queue overflow cannot permanently suppress a later valid voice tail");
  Check(burst.DiagnosticCounts["transmit-queue-full"]==1 && burst.DiagnosticCounts["transmit-frames-missing"]==1,"queue overflow and its counter gap are visible instead of silently discarded");
  var wrapGap=new VoiceEngine("TEST1/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);wrapGap.OnClient(VoiceHeader("WRAP"),0);wrapGap.OnClient(VoiceCodec.SerialVoice("D1E",65530,new byte[65]),0);wrapGap.Tick(0);
  wrapGap.OnClient(VoiceCodec.SerialVoice("D1E",4,tail),200);Check(wrapGap.Tick(200).Network.Count==1,"small forward loss recovery survives the sixteen-bit native counter wrap");
  VoiceEngine e=new VoiceEngine("M5LEE/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  Check(e.OnClient(VoiceHeader("M5LEE"),0).Serial[0]=="D1F00010","voice header receives source-documented short software acknowledgement");
  byte[] voice=new byte[65];for(int i=0;i<65;i++)voice[i]=(byte)(i*3);
  BridgeBatch first=e.OnClient(VoiceCodec.SerialVoice("D1E",0,voice),0);
  Check(first.Serial[0]=="D1E00010" && first.Network.Count==1 && Encoding.ASCII.GetString(first.Network[0],14,10)=="M5LEE     ","outbound stream opens with verified current caller header and voice acknowledgement");
  BridgeBatch key=e.OnClient("P100000",0);
  Check(key.Serial.Count==2 && key.Serial[0]=="B0 0    0000000" && key.Serial[1]=="D1P000B00045TEST10","voice PTT is acknowledged as software sink state without a physical key command");
  Check(e.OnClient("D1C0000",0).Serial[0]=="D1C000B00045TEST10","outbound software status remains coherent while voice is consumed");
  BridgeBatch tick=e.Tick(0);
  Check(tick.Network.Count==1 && BitConverter.ToString(YsfWire.ReceiveVoice(tick.Network[0],50,false))==BitConverter.ToString(voice),"paced outbound engine preserves all encoded voice bytes");
  bool continuous=true;for(int i=1;i<=15;i++){e.OnClient(VoiceCodec.SerialVoice("D1E",i*5,voice),i*100);if(e.Tick(i*100).Network.Count!=1)continuous=false;}
  Check(continuous,"caller metadata remains frozen across an uninterrupted over longer than one second");
  BridgeBatch unkey=e.OnClient("P010000",1600);
  Check(unkey.Serial.Count==1 && unkey.Serial[0]=="B0 0    0000000","software unkey acknowledges without any hardware command");
  BridgeBatch ended=e.Tick(1600);
  Check(ended.Network.Count==1 && (ended.Network[0][34]&1)==1,"explicit unkey emits one network terminator");
  Check(e.Tick(1700).Network.Count==0 && e.OnClient(VoiceCodec.SerialVoice("D1E",0,voice),1700).Network.Count==0,"ended over cannot leak old caller into a new unlabelled stream");
  VoiceEngine stale=new VoiceEngine("M5LEE/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  stale.OnClient(VoiceHeader("M5LEE"),0);stale.OnClient(VoiceCodec.SerialVoice("D1E",0,voice),0);stale.Tick(0);
  Check(stale.Tick(401).Network.Count==1 && stale.Tick(402).Network.Count==0,"stale voice stream emits exactly one terminator and releases");
 }
 static void EngineInboundTests(){
  var addressed=new VoiceEngine("TEST1/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,"12345","TEST1");
  Reject(delegate{new VoiceEngine("TEST1/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,"*****","TEST1");},"room-addressed profile refuses a wildcard destination");
  Reject(delegate{new VoiceEngine("TEST1/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,"00000","TEST1");},"room-addressed profile refuses an unassigned room");
  Reject(delegate{new VoiceEngine("TEST1/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,"12345","OTHER");},"room-addressed profile cannot invent or substitute another radio identity");
  addressed.OnReflector(YsfWire.Packet("TESTVIA","TESTCALL",YsfWire.HeaderFrame("TESTCALL",50,false),0,false),0);
  addressed.OnReflector(YsfWire.Packet("TESTVIA","TESTCALL",YsfWire.VoiceFrame(new byte[65],0,7,50,"TESTCALL"),1,false),20);
  var addressedBatch=addressed.Tick(100);
  Check(addressedBatch.Serial.Contains("D1H001E210020001012345TEST1TESTCALL  "),"explicit room-addressed header carries assigned room and owned emulated-radio identity");
  Check(addressedBatch.Serial.FindAll(delegate(string f){return f.StartsWith("D1H");}).Count==1 && !addressedBatch.Serial.Exists(delegate(string f){return f.StartsWith("D1G");}),"room-addressed short-header path leaves expanded metadata generation to native client");
  Check(!addressed.Tick(200).Serial.Exists(delegate(string f){return f.StartsWith("D1H");}),"room-addressed profile never mixes measured prefix2 continuation slots");
  var complete=new VoiceEngine("TEST1/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,true);
  complete.OnReflector(YsfWire.Packet("TESTVIA","TESTCALL",YsfWire.HeaderFrame("TESTCALL",50,false),0,false),0);
  var headerSlots=new List<string>();bool emptyUplink=true,emptyRem=true;
  for(int step=0;step<8;step++){
   complete.OnReflector(YsfWire.Packet("TESTVIA","TESTCALL",YsfWire.VoiceFrame(new byte[65],step,7,50,"TESTCALL"),step+1,false),20+step*100);
   foreach(string f in complete.Tick(100+step*100).Serial){
    if(!f.StartsWith("D1H"))continue;string slot=f.Substring(15,2);headerSlots.Add(slot);
    if(slot.StartsWith("2"))emptyUplink &= f.Substring(27,10)==new string(' ',10);
    if(slot.StartsWith("3"))emptyRem &= f.Substring(17,20)==new string(' ',20);
   }
  }
  Check(string.Join(",",headerSlots.ToArray())=="10,20,11,12,21,22,31,32","measured receive emits complete genuine header slot sequence without duplicate slots");
  Check(emptyUplink && emptyRem,"measured receive preserves genuine blank uplink and auxiliary fields rather than inventing RF metadata");
  var missingHeader=new VoiceEngine("TEST1/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,true);
  var orphan=YsfWire.Packet("TESTNODE","TESTCALL",YsfWire.VoiceFrame(new byte[65],0,7,50,"TESTCALL"),1,false);
  var orphanResult=missingHeader.OnReflector(orphan,0);
  Check(orphanResult.Serial.Count==0 && missingHeader.DiagnosticCounts.ContainsKey("missing-header") && missingHeader.DiagnosticCounts["missing-header"]==1,"missing receive header is reported separately from a silent voice drop");
  missingHeader.OnReflector(YsfWire.Packet("TESTNODE","TESTCALL",YsfWire.HeaderFrame("TESTCALL",50,false),0,false),1);
  missingHeader.OnReflector(orphan,20);missingHeader.Tick(101);
  Check(missingHeader.DiagnosticCounts.ContainsKey("receive-headers") && missingHeader.DiagnosticCounts["receive-headers"]==1 && missingHeader.DiagnosticCounts.ContainsKey("receive-voice-admitted") && missingHeader.DiagnosticCounts["receive-voice-admitted"]==1 && missingHeader.DiagnosticCounts.ContainsKey("serial-voice-emitted") && missingHeader.DiagnosticCounts["serial-voice-emitted"]==1,"diagnostics distinguish header admission voice admission and serial emission");
  missingHeader.OnReflector(YsfWire.Packet("TESTNODE","TESTCALL",YsfWire.VoiceFrame(new byte[65],1,7,50,"TESTCALL"),8,false),120);
  byte[] damaged=(byte[])orphan.Clone();damaged[35]^=1;missingHeader.OnReflector(damaged,121);
  missingHeader.OnReflector(YsfWire.Packet("TEST1/WX","TEST1/WX",YsfWire.HeaderFrame("TEST1/WX",50,false),0,false),122);
  Check(missingHeader.DiagnosticCounts.ContainsKey("sequence-gap") && missingHeader.DiagnosticCounts["sequence-gap"]==1 && missingHeader.DiagnosticCounts.ContainsKey("invalid-packet") && missingHeader.DiagnosticCounts["invalid-packet"]==1 && missingHeader.DiagnosticCounts.ContainsKey("own-loop") && missingHeader.DiagnosticCounts["own-loop"]==1,"rejection diagnostics distinguish sequence loss malformed packets and own loops");
  var measured=new VoiceEngine("TEST1/WX",50,"D1C000B00005TEST10","B0 0    0000000",false,true);
  var realShape=measured.OnReflector(YsfWire.Packet("M0YSF","M5LEE",YsfWire.HeaderFrame("M5LEE",50,false),0,false),0);
  Check(realShape.Serial.Contains("D1P000B0A015TEST10"),"FTM-100 measured receive carrier uses signal A0 and phase 15");
  measured.OnReflector(YsfWire.Packet("M0YSF","M5LEE",YsfWire.VoiceFrame(new byte[65],0,7,50,"M5LEE"),1,false),20);
  var actual=measured.Tick(100);bool measuredHeader=false,measuredGroup=false,measuredCounter=false;
  foreach(string f in actual.Serial){if(f.StartsWith("D1H001E2000200010") && f.Substring(27,10)=="M5LEE     ")measuredHeader=true;if(f.StartsWith("D1G006C20002000") && f.Length==115)measuredGroup=true;if(f.StartsWith("D1R") && f.Substring(8,4)=="0005")measuredCounter=true;}
  Check(actual.Serial.Contains("D1P000B0A035TEST10"),"FTM-100 measured digital sync uses phase 35");
  Check(measuredHeader && measuredGroup && measuredCounter,"FTM-100 receive metadata uses measured prefix length and first counter");
  string groupFrame=actual.Serial.Find(delegate(string f){return f.StartsWith("D1G");});
  int suffixSum=0;for(int i=75;i<groupFrame.Length-2;i+=2)suffixSum=(suffixSum+Convert.ToInt32(groupFrame.Substring(i,2),16))&255;
  Check(suffixSum==Convert.ToInt32(groupFrame.Substring(groupFrame.Length-2,2),16),"extended D1G suffix passes installed-client additive checksum gate");
  Check(measured.OnClient("D1C0000",101).Serial.Contains("D1C000B0A035TEST10"),"FTM-100 polled receive state agrees with notifications");
  Check(measured.Stop(102).Serial.Contains("D1P000B00005TEST10"),"FTM-100 receive release preserves measured idle mode 05");
  VoiceEngine e=new VoiceEngine("M5LEE/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  BridgeBatch header=e.OnReflector(YsfWire.Packet("M0YSF","M5LEE",YsfWire.HeaderFrame("M5LEE",50,false),0,false),0);
  Check(header.Serial.Count==1 && header.Serial[0]=="D1P000B00011TEST10","inbound stream announces documented carrier state before metadata or voice");
  byte[] voice=new byte[65];for(int i=0;i<65;i++)voice[i]=(byte)(i*7);
  e.OnReflector(YsfWire.Packet("M0YSF","M5LEE",YsfWire.VoiceFrame(voice,0,7,50,"M5LEE"),1,false),20);
  Check(e.Tick(99).Serial.Count==0,"inbound voice waits for bounded digital-sync startup pacing");
  BridgeBatch first=e.Tick(100);bool metadata=false,exact=false,sync=false;
  foreach(string f in first.Serial){if(f.StartsWith("D1H") && f.Substring(27,10)=="M5LEE     ")metadata=true;if(f=="D1P000B00031TEST10")sync=true;if(f.StartsWith("D1R"))exact=BitConverter.ToString(VoiceCodec.ParseVoice(f))==BitConverter.ToString(voice);}
  Check(metadata && exact && sync,"inbound digital sync caller metadata and byte-exact D1R voice are emitted in software");
  string legacyGroup=first.Serial.Find(delegate(string f){return f.StartsWith("D1G");});
  int legacySum=0;for(int i=75;i<legacyGroup.Length-2;i+=2)legacySum=(legacySum+Convert.ToInt32(legacyGroup.Substring(i,2),16))&255;
  Check(legacySum==Convert.ToInt32(legacyGroup.Substring(legacyGroup.Length-2,2),16),"short reference D1G suffix also passes installed-client additive checksum gate");
  e.OnReflector(YsfWire.Packet("M0YSF","M5LEE",YsfWire.HeaderFrame("M5LEE",50,true),2,true),110);
  Check(e.Tick(199).Serial.Count==0,"inbound end preserves the final voice-frame interval");
  BridgeBatch released=e.Tick(200);
  Check(released.Serial.Count==1 && released.Serial[0]=="D1P000B00000TEST10","inbound terminator returns software receiver to idle");
  Check(e.OnClient("P010000",201).Serial[0]=="B0 0    0000000","idle heartbeat resumes after receive release");
  VoiceEngine stale=new VoiceEngine("M5LEE/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  stale.OnReflector(YsfWire.Packet("M0YSF","M5LEE",YsfWire.HeaderFrame("M5LEE",50,false),0,false),0);
  BridgeBatch timed=stale.Tick(401);
  Check(timed.Serial.Count==1 && timed.Serial[0]=="D1P000B00000TEST10","silent incoming header expires without stuck receive or invented voice");
  VoiceEngine duplicate=new VoiceEngine("M5LEE/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  duplicate.OnReflector(YsfWire.Packet("M0YSF","M5LEE",YsfWire.HeaderFrame("M5LEE",50,false),0,false),0);
  byte[] once=YsfWire.Packet("M0YSF","M5LEE",YsfWire.VoiceFrame(voice,0,7,50,"M5LEE"),1,false);
  duplicate.OnReflector(once,20);duplicate.OnReflector(once,21);duplicate.Tick(100);
  Check(duplicate.Tick(200).Serial.Count==0,"duplicated UDP voice packet is never played twice");
  VoiceEngine paced=new VoiceEngine("M5LEE/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  paced.OnClient(VoiceHeader("M5LEE"),0);paced.OnClient(VoiceCodec.SerialVoice("D1E",0,voice),0);paced.Tick(0);
  paced.OnClient(VoiceCodec.SerialVoice("D1E",5,voice),100);paced.Tick(115);
  paced.OnClient(VoiceCodec.SerialVoice("D1E",10,voice),200);
  Check(paced.Tick(205).Network.Count==1 && paced.Tick(205).Network.Count==0,"voice scheduler keeps absolute cadence without drift or catch-up bursts");
 }
 static void EngineLoopTests(){
  byte[] voice=new byte[65];voice[0]=17;
  VoiceEngine e=new VoiceEngine("M5LEE/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  e.OnClient(VoiceHeader("M5LEE"),0);byte[] reflected=e.OnClient(VoiceCodec.SerialVoice("D1E",0,voice),0).Network[0];e.Tick(0);e.OnClient("P010000",100);e.Tick(100);
  Check(e.OnReflector(reflected,200).Serial.Count==0,"late exact reflector echo is suppressed after outbound release");
  VoiceEngine same=new VoiceEngine("M5LEE/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  Check(same.OnReflector(YsfWire.Packet("M5LEE/WX","M5LEE/WX",YsfWire.HeaderFrame("M5LEE/WX",50,false),0,false),0).Serial.Count==0,"direct own-identity stream is never re-injected");
  Check(same.OnReflector(YsfWire.Packet("M5LEE/WX","TEST2",YsfWire.HeaderFrame("TEST2",50,false),0,false),1).Serial.Count==1,"same gateway with a different genuine source is not blanket-blocked");
  same.OnReflector(YsfWire.Packet("M5LEE/WX","TEST2",YsfWire.VoiceFrame(voice,0,7,50,"TEST2"),1,false),20);same.Tick(101);
  same.OnReflector(YsfWire.Packet("M5LEE/WX","TEST2",YsfWire.HeaderFrame("TEST2",50,true),2,true),110);same.Tick(201);
  same.OnClient(VoiceHeader("TEST2"),210);
  Check(same.OnClient(VoiceCodec.SerialVoice("D1E",0,voice),210).Network.Count==0,"recent receive voice reflected back by WIRES-X is not sent to YSF again");
  VoiceEngine stopped=new VoiceEngine("M5LEE/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  stopped.OnClient(VoiceHeader("M5LEE"),0);stopped.OnClient(VoiceCodec.SerialVoice("D1E",0,voice),0);
  BridgeBatch abort=stopped.Stop(1);
  Check(abort.Network.Count==1 && (abort.Network[0][34]&1)==1 && stopped.Tick(100).Network.Count==0,"transport loss abort terminates and discards queued outbound speech");
  stopped.OnReflector(YsfWire.Packet("OTHER","TEST2",YsfWire.HeaderFrame("TEST2",50,false),0,false),200);
  Check(stopped.Stop(201).Serial.Count==1 && stopped.Tick(400).Serial.Count==0,"transport loss abort releases incoming state without queued playback");
 }
 static int Main(string[] args){try{if(args.Length!=1 || args[0]!="--self-test"){Console.WriteLine("OFFLINE ONLY. Usage: WiresXOffline.exe --self-test");return 2;}ParserTests();VoiceTests();SessionTests();ShadowTests();RadioFixtureTests();ConfigurationTests();NativeFichTests();RoomGateTests();EngineOutboundTests();EngineInboundTests();EngineLoopTests();Console.WriteLine("RESULT: "+total+" assertions passed; synthetic offline tests only.");return 0;}catch(Exception e){Console.Error.WriteLine(e.ToString());return 1;}}
}
