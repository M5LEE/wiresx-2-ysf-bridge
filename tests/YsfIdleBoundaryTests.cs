using System;
using System.Reflection;
using CumbriaCQ.Offline;
static class YsfIdleBoundaryTests {
 static int checks;
 static void Check(bool ok,string why){if(!ok)throw new Exception(why);checks++;}
 static readonly MethodInfo Idle=typeof(VoiceEngine).GetMethod("CanChangeYsf");
 static readonly MethodInfo Options=typeof(VoiceEngine).GetMethod("SetYsfOptions");
 static bool Quiet(VoiceEngine e,long now){return (bool)Idle.Invoke(e,new object[]{now});}
 static VoiceEngine Engine(){return new VoiceEngine("TESTGW/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);}
 static int Main(){try{
  Check(Idle!=null && Options!=null,"Live YSF apply requires an explicit idle boundary and options API");
  var e=Engine();Check(Quiet(e,0),"An unused engine must be idle");
  string header="D1F005221016000"+"*****     "+"TESTCALL  "+new string(' ',40)+"09"+new string('0',12);
  e.OnClient(header,100);Check(!Quiet(e,500),"A fresh native header must not be split from its voice");Check(Quiet(e,1101),"An abandoned header must not block room changes indefinitely");
  e.OnClient(header,1200);e.OnClient(VoiceCodec.SerialVoice("D1E",0,new byte[65]),1201);Check(!Quiet(e,1201),"Native speech must delay a YSF switch");
  bool refused=false;try{Options.Invoke(e,new object[]{25,true});}catch(TargetInvocationException ex){refused=ex.InnerException is InvalidOperationException;}Check(refused,"Options must not change during native speech");
  e.OnClient("P010000",1250);e.Tick(1301);Check(Quiet(e,1301),"A completed native over releases the idle boundary");Options.Invoke(e,new object[]{25,true});
  e.OnClient(header,1400);var b=e.OnClient(VoiceCodec.SerialVoice("D1E",0,new byte[65]),1401);var f=new byte[25];Array.Copy(b.Network[0],40,f,0,25);Check(YsfWire.ReadFich(f)[4]==25,"The next header must use the applied DG-ID");e.Stop(1500);
  e=Engine();e.OnReflector(YsfWire.Packet("OTHER","TESTCALL",YsfWire.HeaderFrame("TESTCALL",50,false),0,false),0);Check(!Quiet(e,0),"Incoming YSF speech must delay switching even before serial playout");
  e.OnReflector(YsfWire.Packet("OTHER","TESTCALL",YsfWire.HeaderFrame("TESTCALL",50,true),1,true),50);e.Tick(100);Check(Quiet(e,100),"A completed receive over releases the boundary");
  bool invalid=false;try{Options.Invoke(e,new object[]{128,false});}catch(TargetInvocationException ex){invalid=ex.InnerException is ArgumentException;}Check(invalid,"Invalid DG-ID must fail without changing the engine");
  Console.WriteLine("YSF_IDLE_PASS checks="+checks+" synthetic=true hardware_touched=false");return 0;
 }catch(Exception ex){Console.WriteLine(ex.Message);return 1;}}
}
