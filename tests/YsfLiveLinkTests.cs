using System;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using CumbriaCQ.Configuration;
static class YsfLiveLinkTests {
 static int checks;static Type type;
 static void Check(bool ok,string why){if(!ok)throw new Exception(why);checks++;}
 static object Get(object o,string n){return type.GetProperty(n).GetValue(o,null);}
 static object Call(object o,string n,params object[] a){return type.GetMethod(n).Invoke(o,a);}
 static BridgeSettings Target(int port,string id){return new BridgeSettings{SchemaVersion=1,YsfRoomId=id,YsfRoomName="TEST "+id,YsfHost="127.0.0.1",YsfPort=port,DgId=50,AllowZeroDg=false};}
 static UdpClient Server(){var s=new UdpClient(new IPEndPoint(IPAddress.Loopback,0));s.Client.ReceiveTimeout=1500;return s;}
 static int Port(UdpClient s){return ((IPEndPoint)s.Client.LocalEndPoint).Port;}
 static byte[] Read(UdpClient s,string kind,out IPEndPoint peer){peer=new IPEndPoint(IPAddress.Any,0);byte[] b=s.Receive(ref peer);Check(Encoding.ASCII.GetString(b,0,4)==kind,"Expected "+kind+" from the tested UDP socket");return b;}
 static void Ack(UdpClient server,UdpClient client,object link,long now){IPEndPoint peer;var poll=Read(server,"YSFP",out peer);server.Send(poll,poll.Length,peer);var any=new IPEndPoint(IPAddress.Any,0);client.Receive(ref any);Call(link,"ObserveAck",now);}
 static void Logout(object link,UdpClient server,long start){IPEndPoint peer;for(int i=0;i<3;i++){Call(link,"Advance",start+i*250L,true);Read(server,"YSFU",out peer);}Call(link,"Advance",start+750L,true);}
 static int Main(){try{
  type=typeof(BridgeSettings).Assembly.GetType("CumbriaCQ.Configuration.LiveYsfLink");Check(type!=null,"Live YSF apply must provide an in-process destination switch, not restart WIRES-X");
  using(var old=Server())using(var next=Server())using(var client=new UdpClient(AddressFamily.InterNetwork)){
   var a=Target(Port(old),"00001");var b=Target(Port(next),"00002");client.Connect(IPAddress.Loopback,a.YsfPort);client.Client.ReceiveTimeout=1500;int local=Port(client);object link=Activator.CreateInstance(type,new object[]{client,a,IPAddress.Loopback,"TESTGW/WX"});Call(link,"ObserveAck",0L);
   Call(link,"Request",b,new string('a',32),100L);Call(link,"Advance",100L,false);Call(link,"Advance",200L,false);
   Check((string)Get(link,"State")=="WaitingForIdle","A request during speech must wait for the idle boundary");Check(old.Available==0 && next.Available==0,"Waiting must not send an unlink or reconnect");Check((bool)Call(link,"IsHealthy",200L),"The existing link must stay usable while waiting");
   Logout(link,old,1200L);Check(!(bool)Call(link,"IsHealthy",1950L),"Voice must be gated until the new peer acknowledges");Ack(next,client,link,1960L);Call(link,"Advance",1960L,true);
   Check((string)Get(link,"State")=="Applied","A matching new-peer poll ACK must finish the apply");Check(((BridgeSettings)Get(link,"ActiveSettings")).YsfRoomId=="00002","Active target must be the acknowledged room");Check(Port(client)==local,"The live adapter must keep the same UDP local port");Check((int)Get(link,"Revision")==1,"Exactly one committed apply must be reported");Check((bool)Call(link,"IsHealthy",1960L),"The acknowledged destination must enable the link");
  }
  using(var old=Server())using(var silent=Server())using(var client=new UdpClient(AddressFamily.InterNetwork)){
   var a=Target(Port(old),"00003");client.Connect(IPAddress.Loopback,a.YsfPort);client.Client.ReceiveTimeout=1500;int local=Port(client);object link=Activator.CreateInstance(type,new object[]{client,a,IPAddress.Loopback,"TESTGW/WX"});Call(link,"ObserveAck",0L);
   Call(link,"Request",Target(Port(silent),"00004"),new string('b',32),100L);Logout(link,old,100L);IPEndPoint peer;Read(silent,"YSFP",out peer);Call(link,"Advance",8851L,true);
   Check((string)Get(link,"State")=="UnlinkingForRollback","A new peer that never acknowledges must be logged out before rollback");Logout(link,silent,8851L);Ack(old,client,link,9611L);
   Check((string)Get(link,"State")=="Failed","Rollback must report apply failure, not a false success");Check(((BridgeSettings)Get(link,"ActiveSettings")).YsfRoomId=="00003" && (int)Get(link,"Revision")==0,"Failed apply must retain the original active settings");Check((bool)Call(link,"IsHealthy",9611L),"Old-peer ACK must restore forwarding");Check(Port(client)==local,"Rollback must preserve the live UDP socket and local port");
  }
  using(var old=Server())using(var client=new UdpClient(AddressFamily.InterNetwork)){
   var a=Target(Port(old),"00005");client.Connect(IPAddress.Loopback,a.YsfPort);object link=Activator.CreateInstance(type,new object[]{client,a,IPAddress.Loopback,"TESTGW/WX"});Call(link,"ObserveAck",0L);
   var bad=Target(0,"00006");bool refused=false;try{Call(link,"Request",bad,new string('c',32),10L);}catch(TargetInvocationException ex){refused=ex.InnerException is ArgumentException;}Check(refused && old.Available==0,"Invalid settings must not touch the current link");
   var ipv6=Target(12345,"00006");ipv6.YsfHost="::1";Call(link,"Request",ipv6,new string('c',32),20L);Call(link,"Advance",20L,true);Check((string)Get(link,"State")=="Failed" && old.Available==0 && (bool)Call(link,"IsHealthy",20L),"An incompatible IP family must fail without unlinking the old destination");
   Call(link,"Request",Target(12345,"00007"),new string('d',32),30L);Call(link,"Advance",30L,false);refused=false;try{Call(link,"Request",a,new string('e',32),40L);}catch(TargetInvocationException ex){refused=ex.InnerException is InvalidOperationException;}Check(refused,"A second request must not replace an in-progress handover");Call(link,"Advance",120031L,false);Check((string)Get(link,"State")=="Failed" && old.Available==0,"A continuously busy room must time out without forcing an over boundary");
   Call(link,"Request",a,new string('f',32),120040L);Call(link,"Advance",120040L,true);Check((string)Get(link,"State")=="Applied" && old.Available==0 && (int)Get(link,"Revision")==0,"Applying the already active settings must be a no-op without unlinking");
  }
  Console.WriteLine("YSF_LIVE_LINK_PASS checks="+checks+" real_loopback_udp=true hardware_touched=false");return 0;
 }catch(Exception ex){Console.WriteLine(ex.ToString());return 1;}}
}
