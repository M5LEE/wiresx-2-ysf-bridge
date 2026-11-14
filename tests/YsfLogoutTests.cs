// Copyright (c) 2026 M5LEE.
// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Reflection;
using CumbriaCQ.Configuration;
static class YsfLogoutTests {
 static int checks;
 static void Check(bool ok,string message){if(!ok)throw new Exception(message);checks++;}
 static UdpClient Server(){var s=new UdpClient(new IPEndPoint(IPAddress.Loopback,0));s.Client.ReceiveTimeout=1000;return s;}
 static int Port(UdpClient s){return ((IPEndPoint)s.Client.LocalEndPoint).Port;}
 static BridgeSettings Target(UdpClient s,string id){return new BridgeSettings{SchemaVersion=1,YsfRoomId=id,YsfRoomName="TEST "+id,YsfHost="127.0.0.1",YsfPort=Port(s),DgId=50,AllowZeroDg=false};}
 static void Loss(int lost){
  using(var old=Server())using(var next=Server())using(var client=new UdpClient(AddressFamily.InterNetwork)){
   var a=Target(old,"00001");client.Connect(IPAddress.Loopback,a.YsfPort);int local=Port(client);var link=new LiveYsfLink(client,a,IPAddress.Loopback,"TESTGW/WX");link.ObserveAck(0);
   bool oldMember=true;int unlinks=0,oldPolls=0,newPolls=0;long joinedAt=-1;link.Request(Target(next,"00002"),new string('a',32),100);
   for(long now=100;now<=2100;now+=50){
    link.Advance(now,true);old.Client.Poll(1000,SelectMode.SelectRead);
    while(old.Available>0){var peer=new IPEndPoint(IPAddress.Any,0);var data=old.Receive(ref peer);string kind=Encoding.ASCII.GetString(data,0,4);Check(peer.Port==local,"Logout must use the existing session's UDP source port");if(kind=="YSFU"){unlinks++;if(unlinks>lost)oldMember=false;}else if(kind=="YSFP"){oldPolls++;oldMember=true;}}
    while(next.Available>0){var peer=new IPEndPoint(IPAddress.Any,0);var data=next.Receive(ref peer);Check(!oldMember,"Old reflector must be logged out before the new reflector is joined when an unlink packet is lost");Check(unlinks>=3,"Logout must be retried before the new join");Check(Encoding.ASCII.GetString(data,0,4)=="YSFP","New join must be a poll");newPolls++;joinedAt=now;next.Send(data,data.Length,peer);var from=new IPEndPoint(IPAddress.Any,0);client.Receive(ref from);Check(from.Port==Port(next),"Only the new reflector may acknowledge");link.ObserveAck(now);}
    if(link.State=="Applied")break;
   }
   Check(link.State=="Applied" && link.IsHealthy(2200),"Acknowledged room must eventually apply after bounded logout retries");Check(oldPolls==0,"Old-room keepalives must not register it again during logout");Check(newPolls==1 && joinedAt>=850 && !oldMember,"The handover must be break-before-make with a logout settling interval");Check(Port(client)==local,"Logout must not replace the serial owner or UDP socket");
  }
 }
 static void RollbackLoss(){
  using(var old=Server())using(var next=Server())using(var client=new UdpClient(AddressFamily.InterNetwork)){
   var a=Target(old,"00003");client.Connect(IPAddress.Loopback,a.YsfPort);var link=new LiveYsfLink(client,a,IPAddress.Loopback,"TESTGW/WX");link.ObserveAck(0);link.Request(Target(next,"00004"),new string('b',32),100);bool oldMember=true,newMember=false;int targetUnlinks=0;
   for(long now=100;now<=12000;now+=50){
    link.Advance(now,true);next.Client.Poll(1000,SelectMode.SelectRead);
    while(next.Available>0){var peer=new IPEndPoint(IPAddress.Any,0);var data=next.Receive(ref peer);string kind=Encoding.ASCII.GetString(data,0,4);if(kind=="YSFP")newMember=true;else if(kind=="YSFU"){targetUnlinks++;if(targetUnlinks>1)newMember=false;}}
    while(old.Available>0){var peer=new IPEndPoint(IPAddress.Any,0);var data=old.Receive(ref peer);string kind=Encoding.ASCII.GetString(data,0,4);if(kind=="YSFU")oldMember=false;else if(kind=="YSFP"){Check(!newMember,"Rollback must log out the unsuccessful target before rejoining the previous room when its first unlink is lost");oldMember=true;old.Send(data,data.Length,peer);var from=new IPEndPoint(IPAddress.Any,0);client.Receive(ref from);link.ObserveAck(now);}}
    if(link.State=="Failed")break;
   }
   Check(link.State=="Failed" && oldMember && !newMember,"Rollback must retain only the original acknowledged membership");Check(targetUnlinks>=3 && link.Revision==0,"Rollback cleanup must retry logout and must not commit the failed room");
  }
 }
 static int Main(string[] args){try{if(args.Length==1 && args[0]=="--rollback-only")RollbackLoss();else{Loss(1);Loss(2);RollbackLoss();}Console.WriteLine("YSF_LOGOUT_PASS checks="+checks+" dropped_unlink_cases=3 real_loopback_udp=true native_touched=false");return 0;}catch(Exception e){Console.WriteLine(e.ToString());return 1;}}
}
