extends RefCounted
const HTML := """<!doctype html><html><head><meta charset=utf-8></head><body><script>
// One instance per call. Pass in a microphone MediaStream and the app's signalling callback.
class CheenoMediaCall {
  constructor(config, signal, onAudio) {
    this.pc = new RTCPeerConnection(config);
    this.pending = [];
    this.signal = signal;
    this.pc.onicecandidate = e => { if (e.candidate) signal({k:'ic', m:e.candidate.sdpMid, i:e.candidate.sdpMLineIndex, n:e.candidate.candidate}); };
    this.pc.ontrack = e => { if (e.track.kind === 'audio') onAudio(new MediaStream([e.track])); };
  }
  async start(stream, caller) {
    const track = stream.getAudioTracks()[0];
    if (!track) throw new Error('No microphone track');
    this.pc.addTrack(track, stream);
    if (caller) await this.describe(await this.pc.createOffer());
  }
  async describe(desc) {
    await this.pc.setLocalDescription(desc);
    this.signal({k:'sd',t:desc.type,s:desc.sdp});
  }
  // The signalling adapter must await each message before delivering the next one.
  async receive(msg) {
    if (msg.k === 'ic') {
      const c = {candidate:msg.n,sdpMid:msg.m,sdpMLineIndex:msg.i};
      if (!this.pc.remoteDescription) this.pending.push(c);
      else await this.pc.addIceCandidate(c);
    } else if (msg.k === 'sd') {
      await this.pc.setRemoteDescription({type:msg.t,sdp:msg.s});
      for (const c of this.pending.splice(0)) await this.pc.addIceCandidate(c);
      if (msg.t === 'offer') await this.describe(await this.pc.createAnswer());
    }
  }
  close() { this.pc.close(); this.pending.length = 0; }
}
const emit = x=>CallHost.emit(JSON.stringify(x));
let call, mic, player, queue=Promise.resolve();
window.cmd=wire=>{ const m=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(wire),x=>x.charCodeAt(0))));
queue=queue.then(async()=>{
 if(m.op==='start'){
   mic=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true},video:false});
   mic.getAudioTracks()[0].enabled=!m.muted;
   call=new CheenoMediaCall(m.cfg,msg=>emit({signal:msg}),stream=>{ player=document.createElement('audio');document.body.appendChild(player);player.srcObject=stream;player.play().catch(()=>emit({state:'failed'})); });
   call.pc.onconnectionstatechange=()=>emit({state:call.pc.connectionState});
   await call.start(mic,m.caller);emit({started:true});
 }else if(m.op==='mute'){mic.getAudioTracks()[0].enabled=!m.muted;}
 else if(m.op==='signal')await call.receive(m.data);
}).catch(()=>emit({state:'failed'}));};
emit({ready:true});

</script></body></html>"""
