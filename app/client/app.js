const modeSelector = document.getElementById('mode-selector');
const assistantUI = document.getElementById('assistant-ui');
const transcriptText = document.getElementById('transcript-text');
const responseText = document.getElementById('response-text');
const statusEl = document.getElementById('status');
const activeModeEl = document.getElementById('active-mode');
const pttButton = document.getElementById('ptt');

let ws;
let audioContext;
let sourceNode;
let workletNode;
let currentPlayback;
let mode = localStorage.getItem('selected_mode');

async function ensureSession() {
  try {
    await fetch('/session');
  } catch (err) {
    console.warn('Session fetch failed', err);
  }
}

function showModeSelector() {
  modeSelector.classList.remove('hidden');
  assistantUI.classList.add('hidden');
}

function showAssistantUI() {
  modeSelector.classList.add('hidden');
  assistantUI.classList.remove('hidden');
}

function setStatus(text) {
  statusEl.textContent = text;
}

function stopPlayback() {
  if (currentPlayback) {
    currentPlayback.stop();
    currentPlayback.disconnect();
    currentPlayback = null;
  }
}

async function connectWebSocket() {
  ws = new WebSocket(`ws://${window.location.host}/ws/audio`);
  ws.binaryType = 'arraybuffer';

  ws.onopen = () => {
    ws.send(JSON.stringify({ type: 'set_mode', mode }));
    setStatus('Listening');
  };

  ws.onmessage = async (event) => {
    if (typeof event.data === 'string') {
      const payload = JSON.parse(event.data);
      if (payload.type === 'partial') {
        transcriptText.textContent = payload.text || '...';
        if (payload.text) {
          stopPlayback();
        }
      }
      if (payload.type === 'final') {
        transcriptText.textContent = payload.text || '';
      }
      if (payload.type === 'response') {
        responseText.textContent = payload.text || '';
        setStatus('Speaking');
      }
      if (payload.type === 'mode_set') {
        activeModeEl.textContent = payload.mode || '-';
      }
      if (payload.type === 'error') {
        setStatus(payload.message || 'Error');
      }
      return;
    }

    if (event.data instanceof ArrayBuffer) {
      const audioBuffer = await audioContext.decodeAudioData(event.data.slice(0));
      const source = audioContext.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(audioContext.destination);
      source.onended = () => {
        if (currentPlayback === source) {
          currentPlayback = null;
          setStatus('Listening');
        }
      };
      stopPlayback();
      currentPlayback = source;
      source.start();
    }
  };

  ws.onclose = () => {
    setStatus('Disconnected');
  };
}

async function startAudioCapture() {
  audioContext = new AudioContext({ sampleRate: 16000 });
  await audioContext.audioWorklet.addModule('/static/audio-worklet-processor.js');
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  sourceNode = audioContext.createMediaStreamSource(stream);
  workletNode = new AudioWorkletNode(audioContext, 'pcm-worklet');
  workletNode.port.onmessage = (event) => {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(event.data);
    }
  };
  sourceNode.connect(workletNode);
  workletNode.connect(audioContext.destination);
}

async function init() {
  await ensureSession();
  if (!mode) {
    showModeSelector();
  } else {
    activeModeEl.textContent = mode;
    showAssistantUI();
    await connectWebSocket();
    await startAudioCapture();
  }

  document.querySelectorAll('[data-mode]').forEach((button) => {
    button.addEventListener('click', async () => {
      mode = button.dataset.mode;
      localStorage.setItem('selected_mode', mode);
      activeModeEl.textContent = mode;
      showAssistantUI();
      await connectWebSocket();
      await startAudioCapture();
    });
  });

  pttButton.addEventListener('click', () => {
    if (ws && ws.readyState === WebSocket.OPEN) {
      setStatus('Suggesting');
      ws.send(JSON.stringify({ type: 'ptt' }));
    }
  });
}

init();
