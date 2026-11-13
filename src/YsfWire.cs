// Copyright (c) 2026 M5LEE. MIT; see LICENSE.
using System;
namespace CumbriaCQ.Offline {
 public static class YsfWire {
  public static byte[] ReceiveVoice(byte[] packet,int dgId,bool allowZeroDg){
   if(packet==null || packet.Length!=155 || dgId<0 || dgId>127 || System.Text.Encoding.ASCII.GetString(packet,0,4)!="YSFD")throw new ArgumentException("Received YSFD shape");
   for(int i=4;i<34;i++)if(packet[i]<32 || packet[i]>126)throw new ArgumentException("Received YSFD callsign");
   byte[] sync={0xD4,0x71,0xC9,0x63,0x4D};for(int i=0;i<5;i++)if(packet[35+i]!=sync[i])throw new ArgumentException("Received YSF sync");
   byte[] fich=new byte[25];Array.Copy(packet,40,fich,0,25);int[] fields=ReadFich(fich);
   if(fields[0]!=1 || fields[3]!=2 || (fields[4]!=dgId && !(allowZeroDg && fields[4]==0)))throw new ArgumentException("Received non-voice or wrong DG-ID");
   return VoiceCodec.GetVoice(packet);
  }
  // Exact validation for intact network frames; no radio-error correction is claimed.
  public static int[] ReadFich(byte[] encoded){
   if(encoded==null || encoded.Length!=25)throw new ArgumentException("Receive FICH length");
   byte[] decoded=new byte[13];int d1=0,d2=0,d3=0,d4=0;
   for(int i=0;i<100;i++){
    int at=(i/5)*2+(i%5)*40;int d=Bit(encoded,at)^d3^d4;
    if(Bit(encoded,at+1)!=(d^d1^d2^d4))throw new ArgumentException("Receive FICH convolution");
    Set(decoded,i,d);d4=d3;d3=d2;d2=d1;d1=d;
   }
   for(int i=96;i<100;i++)if(Bit(decoded,i)!=0)throw new ArgumentException("Receive FICH tail");
   int[] words=new int[4];
   for(int i=0;i<4;i++){
    int code=(decoded[i*3]<<16)|(decoded[i*3+1]<<8)|decoded[i*3+2];words[i]=code>>12;
    if(Golay(words[i])!=code)throw new ArgumentException("Receive FICH Golay");
   }
   byte[] raw={(byte)(words[0]>>4),(byte)(((words[0]&15)<<4)|(words[1]>>8)),(byte)words[1],(byte)(words[2]>>4),(byte)(((words[2]&15)<<4)|(words[3]>>8)),(byte)words[3]};
   int crc=Crc(raw,4);if(raw[4]!=(byte)(crc>>8) || raw[5]!=(byte)crc)throw new ArgumentException("Receive FICH CRC");
   return new int[]{raw[0]>>6,(raw[1]>>3)&7,raw[1]&7,raw[2]&3,raw[3]&127};
  }
  public static byte[] Packet(string gateway,string source,byte[] radio,int sequence,bool end){
   if(radio==null || radio.Length!=120 || sequence<0 || sequence>127)throw new ArgumentException("YSFD radio frame or sequence range");
   byte[] sync={0xD4,0x71,0xC9,0x63,0x4D};for(int i=0;i<5;i++)if(radio[i]!=sync[i])throw new ArgumentException("YSF radio sync");
   byte[] packet=new byte[155];Array.Copy(System.Text.Encoding.ASCII.GetBytes("YSFD"),packet,4);
   Array.Copy(TextField(gateway,10),0,packet,4,10);Array.Copy(TextField(source,10),0,packet,14,10);Array.Copy(TextField("ALL",10),0,packet,24,10);
   packet[34]=(byte)((sequence<<1)|(end?1:0));Array.Copy(radio,0,packet,35,120);return packet;
  }
  public static byte[] HeaderFrame(string source,int dgId,bool terminator){
   return HeaderFrame(source,"",dgId,terminator);
  }
  public static byte[] HeaderFrame(string source,string downlink,int dgId,bool terminator){
   byte[] firstData=new byte[20];Array.Copy(TextField("**********",10),firstData,10);Array.Copy(TextField(source,10),0,firstData,10,10);
   byte[] linkData=TextField("",20);Array.Copy(TextField(downlink,10),linkData,10);
   byte[] first=EncodeData(firstData),second=EncodeData(linkData);byte[] frame=BaseFrame(terminator?2:0,0,7,dgId);
   for(int i=0;i<5;i++){Array.Copy(first,i*9,frame,30+i*18,9);Array.Copy(second,i*9,frame,39+i*18,9);}
   return frame;
  }
  static readonly byte[] Whitening={0x93,0xD7,0x51,0x21,0x9C,0x2F,0x6C,0xD0,0xEF,0x0F,0xF8,0x3D,0xF1,0x73,0x20,0x94,0xED,0x1E,0x7C,0xD8};
  static byte[] TextField(string text,int length){
   if(text==null || text.Length>length)throw new ArgumentException("YSF text field length");
   foreach(char c in text)if(c<32 || c>126)throw new ArgumentException("YSF text must be printable ASCII");
   return System.Text.Encoding.ASCII.GetBytes(text.PadRight(length));
  }
  static byte[] EncodeData(byte[] data){
   byte[] input=new byte[data.Length+3];for(int i=0;i<data.Length;i++)input[i]=(byte)(data[i]^Whitening[i]);AddCrc(input,data.Length);
   return Encoded(input,data.Length==10?100:180,data.Length==10?5:9);
  }
  static byte[] BaseFrame(int fi,int fn,int ft,int dgId){
   byte[] frame=new byte[120];byte[] sync={0xD4,0x71,0xC9,0x63,0x4D};Array.Copy(sync,frame,5);Array.Copy(EncodeFich(fi,fn,ft,dgId),0,frame,5,25);return frame;
  }
  public static byte[] VoiceFrame(byte[] voice,int fn,int ft,int dgId,string data){
   if(voice==null || voice.Length!=65)throw new ArgumentException("Encoded voice must be 65 bytes");
   return VoiceDataFrame(voice,fn,ft,dgId,TextField(data,10));
  }
  public static byte[] VoiceDataFrame(byte[] voice,int fn,int ft,int dgId,byte[] data){
   if(voice==null || voice.Length!=65)throw new ArgumentException("Encoded voice must be 65 bytes");
   if(data==null || data.Length!=10)throw new ArgumentException("YSF binary data field must be 10 bytes");
   byte[] encoded=EncodeData(data);byte[] frame=BaseFrame(1,fn,ft,dgId);
   for(int i=0;i<5;i++){Array.Copy(encoded,i*5,frame,30+i*18,5);Array.Copy(voice,i*13,frame,35+i*18,13);}
   return frame;
  }
  static int Bit(byte[] data,int n){return (data[n/8]>>(7-n%8))&1;}
  static void Set(byte[] data,int n,int value){if(value!=0)data[n/8]|=(byte)(0x80>>(n%8));}
  static int Crc(byte[] data,int count){
   int crc=0;
   for(int i=0;i<count;i++){crc^=data[i]<<8;for(int j=0;j<8;j++)crc=((crc<<1)^((crc&0x8000)!=0?0x1021:0))&65535;}
   return (~crc)&65535;
  }
  static void AddCrc(byte[] data,int count){int crc=Crc(data,count);data[count]=(byte)(crc>>8);data[count+1]=(byte)crc;}
  static byte[] Encoded(byte[] data,int steps,int columns){
   byte[] convolution=new byte[(steps*2+7)/8];int d1=0,d2=0,d3=0,d4=0;
   for(int i=0;i<steps;i++){
    int d=Bit(data,i);Set(convolution,i*2,(d^d3^d4)&1);Set(convolution,i*2+1,(d^d1^d2^d4)&1);
    d4=d3;d3=d2;d2=d1;d1=d;
   }
   byte[] output=new byte[convolution.Length];
   for(int i=0;i<steps;i++){int at=(i/columns)*2+(i%columns)*40;Set(output,at,Bit(convolution,i*2));Set(output,at+1,Bit(convolution,i*2+1));}
   return output;
  }
  static int Golay(int data){
   int high=data<<11,remainder=high;
   for(int n=22;n>=11;n--)if((remainder&(1<<n))!=0)remainder^=0xC75<<(n-11);
   int code=high|remainder,parity=0;for(int x=code;x!=0;x>>=1)parity^=x&1;
   return (code<<1)|parity;
  }
  public static byte[] EncodeFich(int fi,int fn,int ft,int dgId){
   if(fi<0 || fi>3 || fn<0 || fn>7 || ft<0 || ft>7 || dgId<0 || dgId>127)throw new ArgumentException("FICH field range");
   // Yaesu C4FM standard, table 4-1 and V/D2 section 4.2.2:
   // CS=10 identifies the callsign data; CS=00 is reserved, not a default.
   byte[] raw={(byte)((fi<<6)|0x20),(byte)((fn<<3)|ft),10,(byte)dgId,0,0};AddCrc(raw,4);
   int[] words={(raw[0]<<4)|(raw[1]>>4),((raw[1]&15)<<8)|raw[2],(raw[3]<<4)|(raw[4]>>4),((raw[4]&15)<<8)|raw[5]};
   byte[] convolutionInput=new byte[13];
   for(int i=0;i<4;i++){int code=Golay(words[i]);convolutionInput[i*3]=(byte)(code>>16);convolutionInput[i*3+1]=(byte)(code>>8);convolutionInput[i*3+2]=(byte)code;}
   return Encoded(convolutionInput,100,5);
  }
 }
}
