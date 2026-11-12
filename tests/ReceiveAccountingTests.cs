using System;
using CumbriaCQ.Offline;
class ReceiveAccountingTests {
 static int Count(VoiceEngine e,string key){int n;return e.DiagnosticCounts.TryGetValue(key,out n)?n:0;}
 static void Check(bool ok,string why){if(!ok)throw new Exception(why);}
 static int Main(){try{
  var e=new VoiceEngine("TESTGW/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);
  e.OnReflector(YsfWire.Packet("TESTVIA","TESTCALL",YsfWire.HeaderFrame("TESTCALL",50,false),0,false),0);
  for(int i=0;i<8;i++)e.OnReflector(YsfWire.Packet("TESTVIA","TESTCALL",YsfWire.VoiceFrame(new byte[65],i%8,7,50,"TESTCALL"),i+1,false),1);
  int admitted=Count(e,"receive-voice-admitted"),rejected=Count(e,"receive-queue-full");
  Console.WriteLine("Valid=8 Admitted="+admitted+" QueueFull="+rejected);
  Check(admitted==4 && rejected==4 && admitted+rejected==8,"Every valid burst input must be admitted or explicitly counted as a capacity rejection");
  Check(Count(e,"sequence-gap")==0,"A capacity drop must not also be counted as an upstream sequence gap");
  var other=new VoiceEngine("TESTGW/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);other.OnReflector(new byte[155],0);
  Check(Count(other,"receive-queue-full")==0 && Count(other,"invalid-packet")==1,"Malformed packets must remain separate from queue-full losses");
  e.Stop(2);Check(Count(e,"receive-queue-full")==4,"Stop must retain diagnostic accounting");Console.WriteLine("RECEIVE_ACCOUNTING_PASS checks=4");return 0;
 }catch(Exception e){Console.WriteLine(e.Message);return 1;}}
}
