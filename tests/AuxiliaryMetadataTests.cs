using System;
using System.Collections.Generic;
using System.Text;
using System.IO;
using CumbriaCQ.Offline;
class AuxiliaryMetadataTests {
 static int checks;
 static readonly byte[] White={0x93,0xD7,0x51,0x21,0x9C,0x2F,0x6C,0xD0,0xEF,0x0F,0xF8,0x3D,0xF1,0x73,0x20,0x94,0xED,0x1E,0x7C,0xD8};
 static void Check(bool b,string message){checks++;if(!b)throw new Exception(message);}
 static int Bit(byte[] b,int i){return (b[i/8]>>(7-i%8))&1;}
 static byte[] Decode(byte[] p){
  byte[] enc=new byte[25];for(int i=0;i<5;i++)Array.Copy(p,65+i*18,enc,i*5,5);
  byte[] raw=new byte[13];int d1=0,d2=0,d3=0,d4=0;for(int i=0;i<100;i++){int n=i/5*2+i%5*40;int d=Bit(enc,n)^d3^d4;Check(Bit(enc,n+1)==(d^d1^d2^d4),"Data FEC");if(d!=0)raw[i/8]|=(byte)(128>>(i%8));d4=d3;d3=d2;d2=d1;d1=d;}
  int crc=0;for(int i=0;i<10;i++){crc^=raw[i]<<8;for(int b=0;b<8;b++)crc=((crc<<1)^((crc&32768)!=0?0x1021:0))&65535;}crc=(~crc)&65535;Check(raw[10]==(byte)(crc>>8)&&raw[11]==(byte)crc,"Data CRC");byte[] data=new byte[10];for(int i=0;i<10;i++)data[i]=(byte)(raw[i]^White[i]);return data;
 }
 static bool Equal(byte[] a,byte[] b){if(a.Length!=b.Length)return false;for(int i=0;i<a.Length;i++)if(a[i]!=b[i])return false;return true;}
 static VoiceEngine Engine(){return new VoiceEngine("TESTGW/WX",50,"D1C000B00000TEST10","B0 0    0000000",false);}
 static byte[] Record(int first,int model){byte[] d=new byte[20];d[0]=(byte)first;d[1]=0x22;d[2]=0x61;d[3]=0x5f;d[4]=(byte)model;d[5]=3;int sum=0;for(int i=0;i<6;i++)sum+=d[i];d[6]=(byte)sum;return d;}
 static string Header(int mode,string caller,byte[] data){string prefix=mode<2?"D1F00522":"D1F006C2";prefix+=(mode%2).ToString()+"016000";return prefix+"**********"+caller.PadRight(10)+new string(' ',40)+BitConverter.ToString(data,0,mode<2?7:20).Replace("-","");}
 static List<byte[]> Voice(VoiceEngine e,int start,int count){var packets=new List<byte[]>();for(int i=start;i<start+count;i++){byte[] v=new byte[65];for(int j=0;j<v.Length;j++)v[j]=(byte)(i+j);packets.AddRange(e.OnClient(VoiceCodec.SerialVoice("D1E",i*5,v),i*100).Network);packets.AddRange(e.Tick(i*100).Network);}return packets;}
 static int[] Info(byte[] p){byte[] f=new byte[25];Array.Copy(p,40,f,0,25);return YsfWire.ReadFich(f);}
 static void Verify(List<byte[]> packets,byte[] expected,string caller){int aux=0;foreach(byte[] p in packets){int[] f=Info(p);Check(Encoding.ASCII.GetString(p,14,10)==caller.PadRight(10),"Caller changed");if(f[0]!=1)continue;Check(f[2]==7,"FT changed unexpectedly");if(f[1]>=6){byte[] block=new byte[10];Array.Copy(expected,(f[1]-6)*10,block,0,10);Check(Equal(Decode(p),block),"Native auxiliary data was discarded or corrupted in FN"+f[1]);aux++;}}Check(aux>=2,"Incomplete auxiliary cycle");}
 static int Main(string[] args){try{
  foreach(int mode in new[]{0,1,2,3})foreach(int first in new[]{1,7}){
   byte[] d=Record(first,0xd5);var e=Engine();Check(e.OnClient(Header(mode,"TESTCALL",d),0).Serial.Contains("D1F00010"),"Metadata ACK changed");var packets=Voice(e,0,16);Verify(packets,d,"TESTCALL");
   int voiceIndex=0;foreach(byte[] p in packets)if(Info(p)[0]==1){byte[] actual=VoiceCodec.GetVoice(p);for(int j=0;j<65;j++)Check(actual[j]==(byte)(voiceIndex+j),"Encoded voice changed");voiceIndex++;}
   if(args.Length>0)using(var w=new StreamWriter(args[0],true))foreach(byte[] p in packets)w.WriteLine(BitConverter.ToString(p).Replace("-",""));
  }
  // Synthetic transport bytes only: no real location or on-air test transmission.
  foreach(int mode in new[]{2,3}){byte[] d=new byte[20];d[0]=0x31;d[1]=0x22;d[2]=0x62;for(int i=3;i<18;i++)d[i]=(byte)(0x80+i);d[18]=3;int sum=0;for(int i=0;i<19;i++)sum+=d[i];d[19]=(byte)sum;var e=Engine();e.OnClient(Header(mode,"TESTCALL",d),0);Verify(Voice(e,0,16),d,"TESTCALL");}
  foreach(int mode in new[]{0,1,2,3}){byte[] bad=Record(7,0x33);bad[6]^=1;var e=Engine();Check(e.OnClient(Header(mode,"TESTCALL",bad),0).Serial.Contains("D1F00010"),"Optional checksum changed ACK");byte[] blank=new byte[20];for(int i=0;i<20;i++)blank[i]=32;Verify(Voice(e,0,8),blank,"TESTCALL");}
  Check(TransmitMetadata.AuxiliaryForFrame(null)==null,"Null native frame accepted");
  foreach(int mode in new[]{0,1,2,3}){byte[] unknown=Record(7,0x33);unknown[2]=0x60;Check(TransmitMetadata.AuxiliaryForFrame(Header(mode,"TESTCALL",unknown))==null,"Unknown auxiliary type accepted");Check(TransmitMetadata.AuxiliaryForFrame(Header(mode,"TESTCALL",new byte[20]))==null,"Absent data fabricated");byte[] end=Record(7,0x33);end[5]=4;Check(TransmitMetadata.AuxiliaryForFrame(Header(mode,"TESTCALL",end))==null,"Missing end marker accepted");}
  var frozen=Engine();byte[] a=Record(7,0x33),b=Record(1,0x2b);frozen.OnClient(Header(3,"TESTCALL",a),0);var firstPackets=Voice(frozen,0,4);frozen.OnClient(Header(3,"OTHERTEST",b),350);firstPackets.AddRange(Voice(frozen,4,4));Verify(firstPackets,a,"TESTCALL");
  frozen.Stop(800);frozen.OnClient(Header(2,"OTHERTEST",b),800);Verify(Voice(frozen,8,8),b,"OTHERTEST");
  var reset=Engine();reset.OnClient(Header(3,"TESTCALL",a),0);Voice(reset,0,2);reset.SetConnectedRoom("12345",200);Check(Voice(reset,2,1).Count==0,"Room reset retained caller metadata");
  Console.WriteLine("AUXILIARY_METADATA_PASS checks="+checks+" binary_safe=true voice_unchanged=true source_bound=true");return 0;
 }catch(Exception ex){Console.WriteLine("AUXILIARY_METADATA_FAIL "+ex.Message);return 1;}}
}
