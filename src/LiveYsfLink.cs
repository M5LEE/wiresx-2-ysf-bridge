// Copyright (c) 2026 M5LEE.
// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using System.Text.RegularExpressions;
namespace CumbriaCQ.Configuration {
 public sealed class LiveYsfLink {
  readonly UdpClient socket;readonly byte[] poll,unlink;
  BridgeSettings active,pending;IPEndPoint peer,next,previous;Task<IPAddress[]> resolving;
  long requestedAt,phaseAt,lastAck=-1,targetAck=-1,logoutNextAt;int revision,generation,logoutAttempts,logoutSent;bool restoreLogout;
  public string State {get;private set;} public string Message {get;private set;} public string RequestId {get;private set;}
  public int Revision {get{return revision;}} public int TransportGeneration {get{return generation;}}
  public string PeerAddress {get{return peer.Address.ToString();}} public int PeerPort {get{return peer.Port;}}
  public BridgeSettings ActiveSettings {get{return Copy(active);}}
  bool LoggingOut {get{return State=="Unlinking" || State=="UnlinkingForRollback";}}
  public bool Pending {get{return State=="Resolving" || State=="WaitingForIdle" || LoggingOut || State=="Connecting" || State=="Restoring";}}
  public bool Paused {get{return LoggingOut || State=="Connecting" || State=="Restoring" || State=="RollbackFailed";}}
  public bool CanPoll {get{return !LoggingOut && !(State=="RollbackFailed" && !peer.Equals(previous));}}
  static BridgeSettings Copy(BridgeSettings s){return new BridgeSettings{SchemaVersion=s.SchemaVersion,YsfRoomId=s.YsfRoomId,YsfRoomName=s.YsfRoomName,YsfHost=s.YsfHost,YsfPort=s.YsfPort,DgId=s.DgId,AllowZeroDg=s.AllowZeroDg};}
  public LiveYsfLink(UdpClient socket,BridgeSettings settings,IPAddress address,string gateway){
   if(socket==null || address==null || !Regex.IsMatch(gateway??"",@"\A[A-Z0-9][A-Z0-9 /-]{0,9}\z"))throw new ArgumentException("YSF link identity");
   SettingsStore.Validate(settings);this.socket=socket;active=Copy(settings);peer=new IPEndPoint(address,settings.YsfPort);poll=Encoding.ASCII.GetBytes("YSFP"+gateway.PadRight(10));unlink=Encoding.ASCII.GetBytes("YSFU"+gateway.PadRight(10));State="Idle";Message="YSF destination loaded";RequestId="";
  }
  public bool IsHealthy(long now){return !Paused && lastAck>=0 && now>=lastAck && now-lastAck<=15000;}
  public void ObserveTransportError(){lastAck=-1;targetAck=-1;}
  public void ObserveAck(long now){
   if(!CanPoll)return;
   if(State=="Connecting")targetAck=now;
   else{lastAck=now;if(State=="Restoring" || State=="RollbackFailed")Fail("Apply failed; the previous YSF destination has reconnected");}
  }
  public void Request(BridgeSettings settings,string id,long now){
   SettingsStore.Validate(settings);if(!Regex.IsMatch(id??"",@"\A[a-f0-9]{32}\z"))throw new ArgumentException("YSF apply request ID");
   if(Pending || State=="RollbackFailed" || (resolving!=null && !resolving.IsCompleted))throw new InvalidOperationException("A YSF apply is already pending or recovering");
   pending=Copy(settings);RequestId=id;requestedAt=now;targetAck=-1;next=null;State="Resolving";Message="Resolving the saved YSF destination";
   if(pending.YsfRoomId==active.YsfRoomId && pending.YsfRoomName==active.YsfRoomName && pending.YsfHost==active.YsfHost && pending.YsfPort==active.YsfPort && pending.DgId==active.DgId && pending.AllowZeroDg==active.AllowZeroDg){pending=null;State="Applied";Message="These YSF settings are already active; WIRES-X was not restarted";return;}
   IPAddress literal;resolving=IPAddress.TryParse(pending.YsfHost,out literal)?Task.FromResult(new[]{literal}):Dns.GetHostAddressesAsync(pending.YsfHost);
  }
  public void Advance(long now,bool idle){
   if(State=="Resolving"){
    if(now-requestedAt>=10000){Fail("YSF DNS lookup timed out; previous destination retained");return;}
    if(!resolving.IsCompleted)return;
    try{foreach(var address in resolving.GetAwaiter().GetResult())if(address.AddressFamily==socket.Client.AddressFamily){next=new IPEndPoint(address,pending.YsfPort);break;}}
    catch(SocketException){Fail("Could not resolve the saved YSF host; previous destination retained");return;}
    if(next==null){Fail("The new host needs a different IP family; previous destination retained");return;}
    State="WaitingForIdle";Message="Waiting for the current over to finish";
   }
   if(State=="WaitingForIdle" && now-requestedAt>=120000){Fail("No idle window within two minutes; previous destination retained");return;}
   if(State=="WaitingForIdle" && idle){
    // Drain only already-queued old-peer datagrams, never block serial service.
    var any=new IPEndPoint(peer.AddressFamily==AddressFamily.InterNetwork?IPAddress.Any:IPAddress.IPv6Any,0);
    for(int i=0;i<64 && socket.Available>0;i++)socket.Receive(ref any);
    if(socket.Available>0)return;
    previous=peer;BeginLogout(now,false);
   }
   if(LoggingOut){AdvanceLogout(now);return;}
   if(State=="Connecting" && ((targetAck<0 && now-phaseAt>=8000) || now-requestedAt>=120000)){Restore(now);return;}
   if(State=="Connecting" && targetAck>=0 && now-targetAck<=15000 && idle){
    active=Copy(pending);pending=null;revision++;lastAck=targetAck;State="Applied";Message="YSF room applied without restarting WIRES-X";
   }
   if(State=="Restoring" && now-phaseAt>=8000){State="RollbackFailed";Message="Apply failed; previous YSF destination is selected but has not acknowledged";pending=null;}
  }
  void BeginLogout(long now,bool restoring){
   restoreLogout=restoring;logoutAttempts=0;logoutSent=0;logoutNextAt=now;phaseAt=now;lastAck=-1;targetAck=-1;
   State=restoring?"UnlinkingForRollback":"Unlinking";Message=restoring?"Logging out of the unsuccessful YSF destination before returning":"Logging out of the previous YSF room before joining the new room";
  }
  void AdvanceLogout(long now){
   // Space control retries across adapter ticks; never sleep on serial service.
   if(logoutAttempts<3 && now>=logoutNextAt){logoutAttempts++;logoutNextAt=now+250;try{if(socket.Send(unlink,unlink.Length)==unlink.Length)logoutSent++;}catch(SocketException){}}
   if(logoutAttempts<3 || now<logoutNextAt || now-phaseAt<750)return;
   if(logoutSent!=3){
    if(restoreLogout){State="RollbackFailed";pending=null;Message="Apply failed; could not log out of the unsuccessful YSF destination, so reconnecting is paused";}
    else Fail("Could not send the previous YSF room logout; the new room was not joined");
    return;
   }
   var any=new IPEndPoint(peer.AddressFamily==AddressFamily.InterNetwork?IPAddress.Any:IPAddress.IPv6Any,0);
   for(int i=0;i<64 && socket.Available>0;i++)socket.Receive(ref any);
   if(restoreLogout){ReconnectPrevious(now);return;}
   try{socket.Connect(next);peer=next;generation++;phaseAt=now;State="Connecting";Message="Checking the new YSF connection; WIRES-X remains running";socket.Send(poll,poll.Length);}
   catch(SocketException){Restore(now);}
  }
  void Restore(long now){
   if(!peer.Equals(previous)){BeginLogout(now,true);return;}
   ReconnectPrevious(now);
  }
  void ReconnectPrevious(long now){
   lastAck=-1;targetAck=-1;phaseAt=now;State="Restoring";Message="New YSF destination did not respond; restoring the previous destination";
   try{socket.Connect(previous);peer=previous;generation++;socket.Send(poll,poll.Length);}
   catch(SocketException){State="RollbackFailed";Message="Apply failed; previous YSF connection could not be restored";pending=null;}
  }
  void Fail(string message){State="Failed";Message=message;pending=null;}
 }
}
