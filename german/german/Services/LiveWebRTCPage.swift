import Foundation

enum LiveWebRTCPage {
    static let html = #"""
    <!doctype html><html><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; media-src blob:; connect-src 'none'">
    </head><body><audio id="reply" autoplay playsinline></audio><script>
    'use strict';
    const post = event => window.webkit.messageHandlers.live.postMessage(event);
    const reply = document.getElementById('reply');
    let peer, events, microphone, context, inputMeter, outputMeter, timer, fixtureSource, fixtureDestination;
    let closing = false, started = false, muted = false, sentSeconds = 0, lastTick = 0;
    let lastSound = 0, hadReply = false, closeResolve, disconnectedTimer;
    function checkOpen() { if (closing) throw new Error('Conversation closed.'); }
    function failure(message) { if (!closing) post({type:'local.error', message}); }
    function meter(stream) {
      const analyser = context.createAnalyser(); analyser.fftSize = 1024;
      context.createMediaStreamSource(stream).connect(analyser);
      return analyser;
    }
    function rms(analyser) {
      if (!analyser) return 0;
      const samples = new Float32Array(analyser.fftSize);
      analyser.getFloatTimeDomainData(samples);
      return Math.sqrt(samples.reduce((sum, value) => sum + value * value, 0) / samples.length);
    }
    function level(value) { return value > 0 ? Math.max(0, Math.min(1, (20 * Math.log10(value) + 60) / 60)) : 0; }
    function stopMicrophone() {
      microphone?.getTracks().forEach(track => { track.enabled = false; track.stop(); });
      try { fixtureSource?.stop(); } catch (_) {}
    }
    function cleanup() {
      clearInterval(timer); clearTimeout(disconnectedTimer);
      stopMicrophone(); reply.pause(); reply.srcObject = null;
      events?.close(); peer?.close(); context?.close();
    }
    window.live = {
      async prepare(inputName, outputName, fixture) {
        try {
          checkOpen();
          context = new AudioContext(); await context.resume(); checkOpen();
          if (fixture) {
            // WebKit gates host ICE candidates on capture authorization. Discard
            // this local input immediately; only the fixture track is ever sent.
            const authorization = await navigator.mediaDevices.getUserMedia({audio:true});
            authorization.getTracks().forEach(track => track.stop()); checkOpen();
            const bytes = Uint8Array.from(atob(fixture), c => c.charCodeAt(0));
            const decoded = await context.decodeAudioData(bytes.buffer); checkOpen();
            const destination = context.createMediaStreamDestination(); fixtureDestination = destination;
            fixtureSource = context.createBufferSource(); fixtureSource.buffer = decoded;
            fixtureSource.connect(destination); microphone = destination.stream;
          } else {
            const constraints = {echoCancellation:true, noiseSuppression:true, autoGainControl:true};
            microphone = await navigator.mediaDevices.getUserMedia({audio: constraints});
            if (closing) { stopMicrophone(); return; }
            if (inputName && microphone.getAudioTracks()[0].label !== inputName) {
              const devices = await navigator.mediaDevices.enumerateDevices(); checkOpen();
              const selected = devices.find(d => d.kind === 'audioinput' && d.label === inputName);
              stopMicrophone();
              if (!selected) throw new Error('The selected microphone is unavailable to voice chat. Choose another input in Settings.');
              microphone = await navigator.mediaDevices.getUserMedia({audio: {...constraints, deviceId:{exact:selected.deviceId}}});
              if (closing) { stopMicrophone(); return; }
            }
            microphone.getAudioTracks()[0].addEventListener('ended', () => failure('Your microphone disconnected. Start a new conversation.'));
          }
          inputMeter = meter(microphone);
          post({type:'local.devices', input: fixture ? 'Synthetic speech (test)' : microphone.getAudioTracks()[0].label, output:outputName});
          peer = new RTCPeerConnection();
          peer.addEventListener('connectionstatechange', () => {
            clearTimeout(disconnectedTimer);
            if (peer.connectionState === 'failed') failure('The voice connection failed. Check your network and reconnect.');
            if (peer.connectionState === 'disconnected') disconnectedTimer = setTimeout(() => failure('The voice connection was lost. Please reconnect.'), 5000);
          });
          peer.addEventListener('track', event => {
            const stream = new MediaStream([event.track]);
            reply.srcObject = stream; outputMeter = meter(stream);
            reply.play().catch(() => failure('Voice playback was blocked. Close this conversation and try again.'));
          });
          for (const track of microphone.getAudioTracks()) peer.addTrack(track, microphone);
          events = peer.createDataChannel('oai-events');
          events.addEventListener('message', ({data}) => {
            try {
              const event = JSON.parse(data);
              if (event.type === 'session.started') {
                started = true;
                if (fixtureSource) fixtureSource.start(context.currentTime + 0.5);
              }
              if (event.type === 'session.closed') {
                closeResolve?.();
                if (!closing) { closing = true; post(event); cleanup(); }
                return;
              }
              if (!closing) post(event);
            } catch (_) { failure('Invalid voice session event. Please reconnect.'); }
          });
          events.addEventListener('close', () => failure('The voice event connection closed. Please reconnect.'));
          const offer = await peer.createOffer(); checkOpen();
          await peer.setLocalDescription(offer); checkOpen();
          if (peer.iceGatheringState !== 'complete') await new Promise((resolve, reject) => {
            const deadline = setTimeout(() => { peer.removeEventListener('icegatheringstatechange', changed); reject(new Error('Voice connection setup timed out.')); }, 10000);
            function changed() { if (peer.iceGatheringState === 'complete') { clearTimeout(deadline); peer.removeEventListener('icegatheringstatechange', changed); resolve(); } }
            peer.addEventListener('icegatheringstatechange', changed); changed();
          });
          checkOpen();
          lastTick = performance.now();
          timer = setInterval(() => {
            const now = performance.now(), output = rms(outputMeter);
            if (started && !muted) sentSeconds += (now - lastTick) / 1000;
            lastTick = now;
            if (output > 0.002) {
              lastSound = now;
              if (!hadReply) { hadReply = true; post({type:'local.playback', message:'Receiving tutor audio'}); }
            }
            post({type:'local.level', input:muted ? 0 : level(rms(inputMeter)), seconds:sentSeconds, speaking:now - lastSound < 450 && lastSound > 0});
          }, 100);
          post({type:'local.offer', sdp:peer.localDescription.sdp});
        } catch (error) { failure(error.message || 'Could not start voice audio.'); cleanup(); }
      },
      async accept(sdp) { checkOpen(); await peer.setRemoteDescription({type:'answer', sdp}); },
      async speakFixture(encoded) {
        checkOpen();
        if (!fixtureDestination) throw new Error('No synthetic input is active.');
        const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
        const buffer = await context.decodeAudioData(bytes.buffer); checkOpen();
        try { fixtureSource?.stop(); } catch (_) {}
        fixtureSource = context.createBufferSource(); fixtureSource.buffer = buffer;
        fixtureSource.connect(fixtureDestination); fixtureSource.start();
      },
      mute(value) {
        muted = value;
        // Disabling the outgoing track sends silence; it never pauses incoming audio.
        microphone?.getAudioTracks().forEach(track => { track.enabled = !value; });
      },
      async testSpeaker() {
        checkOpen(); await context.resume();
        const oscillator = context.createOscillator(), gain = context.createGain();
        const now = context.currentTime;
        oscillator.frequency.value = 660;
        gain.gain.setValueAtTime(0, now); gain.gain.linearRampToValueAtTime(0.12, now + 0.02);
        gain.gain.linearRampToValueAtTime(0, now + 0.3);
        oscillator.connect(gain).connect(context.destination); oscillator.start(); oscillator.stop(now + 0.3);
        post({type:'local.playback', message:'Playing a short test sound…'});
      },
      async close() {
        if (closing) { cleanup(); return; }
        closing = true;
        stopMicrophone(); reply.pause(); clearInterval(timer);
        if (events?.readyState === 'open' && started) {
          await new Promise(resolve => {
            const deadline = setTimeout(resolve, 15000);
            closeResolve = () => { clearTimeout(deadline); resolve(); };
            events.send(JSON.stringify({type:'session.close'}));
          });
        }
        cleanup();
      }
    };
    post({type:'local.ready'});
    </script></body></html>
    """#
}
