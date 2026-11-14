// Copyright (c) 2026 M5LEE.
// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.Collections.Generic;
namespace CumbriaCQ.Offline {
 public sealed class TransmitProfile {
  readonly byte[] auxiliary;
  public readonly int FrameTotal;
  public readonly string Uplink,Remarks;
  internal TransmitProfile(byte[] data,string uplink,string remarks){auxiliary=data;FrameTotal=data==null?5:data.Length<=10?6:7;Uplink=uplink;Remarks=remarks;}
  public byte[] DataBlock(int number){
   if(number<6 || number>FrameTotal)throw new ArgumentException("Auxiliary frame number");
   byte[] block=new byte[10];int offset=(number-6)*10;Array.Copy(auxiliary,offset,block,0,Math.Min(10,auxiliary.Length-offset));return block;
  }
 }
 public static class TransmitMetadata {
  // D1F is the write-direction twin of D1G: six fixed ASCII fields,
  // with either the short position slot or the extended 20-byte hex slot.
  // Recognising this envelope only acknowledges metadata; it never keys RF.
  public static string SourceForFrame(string frame){
   if(frame==null || (frame.Length!=89 && frame.Length!=115))return null;
   if(!System.Text.RegularExpressions.Regex.IsMatch(frame,@"\A(?:D1F00522[01]016000[ -~]{74}|D1F006C2[01]016000[ -~]{60}[0-9A-F]{40})\z"))return null;
   string source=frame.Substring(25,10).TrimEnd(' ');
   return System.Text.RegularExpressions.Regex.IsMatch(source,@"\A[A-Z0-9][A-Z0-9 /-]{0,9}\z")?source:null;
  }
  public static TransmitProfile ProfileForFrame(string frame){
   if(SourceForFrame(frame)==null)return null;
   return new TransmitProfile(Auxiliary(frame.Substring(75)),frame.Substring(45,10),frame.Substring(55,20));
  }
  static byte[] Auxiliary(string hex){
   if(!System.Text.RegularExpressions.Regex.IsMatch(hex,@"\A(?:[0-9A-F]{14}|[0-9A-F]{40})\z"))return null;
   byte[] data=new byte[hex.Length/2];for(int i=0;i<data.Length;i++)data[i]=Convert.ToByte(hex.Substring(i*2,2),16);
   int length=data[1]==0x22 && data[2]==0x61?7:(data[1]==0x22 && data[2]==0x62)||(data[1]==0x47 && data[2]==0x64)?20:0;
   if(length==0 || data.Length<length || data[length-2]!=3)return null;
   int sum=0;for(int i=0;i<length-1;i++)sum+=data[i];if((byte)sum!=data[length-1])return null;
   for(int i=length;i<data.Length;i++)if(data[i]!=0 && data[i]!=32)return null;
   // The first byte differs between genuine formats; do not assume it is a length.
   Array.Resize(ref data,length);return data;
  }
 }
 public static class NodeDataEcho {
  // This is an explicitly experimental software echo, not a captured radio reply.
  public static byte[] ForFrame(string frame){
   if(frame==null || !System.Text.RegularExpressions.Regex.IsMatch(frame,@"\AD1F00FA20011000[ -~]{242}\z"))return null;
   return System.Text.Encoding.ASCII.GetBytes("\x01"+frame+"\x04");
  }
 }
 public sealed class ConfigurationReply {
  readonly string expected; readonly byte[] wire;
  public ConfigurationReply(string query,string reply){
   if(query==null || !System.Text.RegularExpressions.Regex.IsMatch(query,@"\AD1M00457000([ 0-9]{3}\.[0-9]{5}[+-][0-9]{3}\.[0-9]{5}[0-9A-F]{13}){2}F\z"))throw new ArgumentException("Configuration query shape");
   string paired=query.Substring(0,7)+"5000"+query.Substring(11,64)+"0";
   if(reply!=paired)throw new ArgumentException("Configuration fixture is not the measured response for this profile");
   expected=query;wire=System.Text.Encoding.ASCII.GetBytes("\x01"+reply+"\x04");
  }
  public byte[] ForQuery(string query){return query==expected?(byte[])wire.Clone():null;}
 }
 public sealed class RadioIdReply {
  readonly byte[] wire;
  public RadioIdReply(string fixture){
   int n;
   if(fixture==null || fixture.Length<8 || !fixture.StartsWith("D1V") || !int.TryParse(fixture.Substring(3,4),System.Globalization.NumberStyles.HexNumber,System.Globalization.CultureInfo.InvariantCulture,out n) || n<1 || n>256 || fixture.Length!=n+7)throw new ArgumentException("Identification fixture shape/length");
   foreach(char c in fixture)if(c<32 || c>126)throw new ArgumentException("Identification fixture character");
   wire=System.Text.Encoding.ASCII.GetBytes("\x01"+fixture+"\x04");
  }
  public byte[] ForQuery(string query){return query=="D1V0000"?(byte[])wire.Clone():null;}
 }
 public sealed class ShadowRouter {
  public string Classify(string frame){
   if(frame=="M00" || frame=="M10" || frame=="R6423")return "hardware-query";
   if(frame=="D1V0000" || frame=="D1C0000")return "missing-radio-fixture";
   if(frame!=null && frame.StartsWith("D1E")){try{VoiceCodec.ParseVoice(frame);return "offline-voice";}catch(ArgumentException){return "blocked";}}
   return "blocked";
  }
 }
 public sealed class OfflineSession {
  readonly int capacity; readonly long gap;readonly Queue<byte[]> pending=new Queue<byte[]>();long lastTime;int expected=-1;bool active;
  public OfflineSession(int capacity,long gap){if(capacity<1 || gap<1)throw new ArgumentException("capacity/gap");this.capacity=capacity;this.gap=gap;}
  public bool Active {get{return active;}}
  public bool Begin(long now){if(active)return false;pending.Clear();expected=-1;lastTime=now;active=true;return true;}
  void Expire(long now){if(active && now-lastTime>gap)End();}
  public bool Push(int counter,byte[] voice,long now){
   Expire(now);if(!active || now<lastTime || voice==null || voice.Length!=65 || pending.Count>=capacity)return false;
   counter &=65535;if(expected>=0 && counter!=expected)return false;
   pending.Enqueue((byte[])voice.Clone());expected=(counter+5)&65535;lastTime=now;return true;
  }
  public byte[] Take(long now){Expire(now);return pending.Count>0?pending.Dequeue():null;}
  public void End(){active=false;expected=-1;pending.Clear();}
 }
 public static class VoiceCodec {
  public static string SerialVoice(string direction,int counter,byte[] payload){
   if(direction!="D1E" && direction!="D1R")throw new ArgumentException("direction");
   if(payload==null || payload.Length!=65)throw new ArgumentException("voice length");
   return direction+"00892"+(counter&65535).ToString("X4")+"00"+BitConverter.ToString(payload).Replace("-","");
  }
  public static byte[] ParseVoice(string body){
   if(body==null || body.Length!=144 || !(body.StartsWith("D1E00892") || body.StartsWith("D1R00892")))throw new ArgumentException("serial voice frame");
   for(int i=8;i<body.Length;i++)if(!Uri.IsHexDigit(body[i]))throw new ArgumentException("non hex serial payload");
   byte[] bytes=new byte[65];for(int i=0;i<65;i++)bytes[i]=Convert.ToByte(body.Substring(14+i*2,2),16);return bytes;
  }
  static void ValidatePacket(byte[] packet){if(packet==null || packet.Length!=155 || packet[0]!=89 || packet[1]!=83 || packet[2]!=70 || packet[3]!=68)throw new ArgumentException("YSFD packet shape");}
  public static byte[] PutVoice(byte[] template,byte[] voice){
   ValidatePacket(template);if(voice==null || voice.Length!=65)throw new ArgumentException("voice length");
   byte[] packet=(byte[])template.Clone();for(int i=0;i<5;i++)Array.Copy(voice,i*13,packet,70+i*18,13);return packet;
  }
  public static byte[] GetVoice(byte[] packet){ValidatePacket(packet);byte[] voice=new byte[65];for(int i=0;i<5;i++)Array.Copy(packet,70+i*18,voice,i*13,13);return voice;}
 }
 public sealed class FrameParser {
  readonly int maximum; readonly System.Text.StringBuilder buffer=new System.Text.StringBuilder(); bool active;
  public FrameParser(int max){if(max<1)throw new ArgumentOutOfRangeException("max");maximum=max;}
  public List<string> Feed(byte[] bytes){
   List<string> result=new List<string>();
   foreach(byte b in bytes){
    if(b==1){buffer.Length=0;active=true;continue;}
    if(!active)continue;
    if(b==4){if(buffer.Length>0)result.Add(buffer.ToString());buffer.Length=0;active=false;continue;}
    if(b<32 || b>126 || buffer.Length>=maximum){buffer.Length=0;active=false;continue;}
    buffer.Append((char)b);
   }
   return result;
  }
 }
}
