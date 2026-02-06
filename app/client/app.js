const modeSelect = document.getElementById('mode-select');
const liveBetaToggle = document.getElementById('live-beta');
const showAlternativesToggle = document.getElementById('show-alternatives');
const pttButton = document.getElementById('ptt');
const statusEl = document.getElementById('status');
const phraseEl = document.getElementById('phrase');
const scoreEl = document.getElementById('score');
const clarityEl = document.getElementById('clarity');
const centerednessEl = document.getElementById('centeredness');
const riskEl = document.getElementById('risk');
const activeSilenceEl = document.getElementById('active-silence');
const alternativesEl = document.getElementById('alternatives');
const transcriptEl = document.getElementById('transcript');

const STORAGE_KEYS = {
  mode: 'mirror_mode',
  live: 'mirror_live_beta',
  alternatives: 'mirror_show_alternatives',
};

let audioContext;
let workletNode;
let sourceNode;
let mediaStream;
let gainNode;
let isRecording = false;
let buffers = [];

function setStatus(text) {
  statusEl.textContent = text;
}

function updateStorage() {
  localStorage.setItem(STORAGE_KEYS.mode, modeSelect.value);
  localStorage.setItem(STORAGE_KEYS.live, String(liveBetaToggle.checked));
  localStorage.setItem(STORAGE_KEYS.alternatives, String(showAlternativesToggle.checked));
}

function loadStorage() {
  const storedMode = localStorage.getItem(STORAGE_KEYS.mode);
  if (storedMode) {
    modeSelect.value = storedMode;
  }
  liveBetaToggle.checked = localStorage.getItem(STORAGE_KEYS.live) === 'true';
  showAlternativesToggle.checked = localStorage.getItem(STORAGE_KEYS.alternatives) === 'true';
}

function mergeBuffers(chunks) {
  const length = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const result = new Int16Array(length);
  let offset = 0;
  chunks.forEach((chunk) => {
    result.set(chunk, offset);
    offset += chunk.length;
  });
  return result;
}

function encodeWav(samples, sampleRate) {
  const buffer = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(buffer);

  function writeString(offset, text) {
    for (let i = 0; i < text.length; i += 1) {
      view.setUint8(offset + i, text.charCodeAt(i));
    }
  }

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + samples.length * 2, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeString(36, 'data');
  view.setUint32(40, samples.length * 2, true);

  let offset = 44;
  for (let i = 0; i < samples.length; i += 1) {
    view.setInt16(offset, samples[i], true);
    offset += 2;
  }

  return buffer;
}

async function initAudio() {
  audioContext = new AudioContext({ sampleRate: 16000 });
  await audioContext.audioWorklet.addModule('/static/audio-worklet-processor.js');
  mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
  sourceNode = audioContext.createMediaStreamSource(mediaStream);
  workletNode = new AudioWorkletNode(audioContext, 'pcm-worklet');
  gainNode = audioContext.createGain();
  gainNode.gain.value = 0;
  workletNode.port.onmessage = (event) => {
    if (!isRecording) {
      return;
    }
    buffers.push(new Int16Array(event.data));
  };
  sourceNode.connect(workletNode);
  workletNode.connect(gainNode);
  gainNode.connect(audioContext.destination);
}

async function startRecording() {
  if (isRecording) {
    return;
  }
  buffers = [];
  setStatus('Registrazione in corso...');
  pttButton.classList.add('is-recording');
  isRecording = true;
  if (!audioContext) {
    await initAudio();
  }
}

async function stopRecording() {
  if (!isRecording) {
    return;
  }
  isRecording = false;
  pttButton.classList.remove('is-recording');
  setStatus('Invio in corso...');

  const samples = mergeBuffers(buffers);
  const wavBuffer = encodeWav(samples, 16000);
  const blob = new Blob([wavBuffer], { type: 'audio/wav' });

  const formData = new FormData();
  formData.append('file', blob, 'audio.wav');
  formData.append('mode', modeSelect.value);
  formData.append('show_alternatives', String(showAlternativesToggle.checked));
  formData.append('live_beta', String(liveBetaToggle.checked));

  try {
    const response = await fetch('/api/coach/analyze_audio', {
      method: 'POST',
      body: formData,
    });
    if (!response.ok) {
      throw new Error('HTTP error');
    }
    const payload = await response.json();
    renderResponse(payload);
    setStatus('Risposta pronta');
  } catch (err) {
    console.warn('Analyze failed', err);
    setStatus('Errore durante analisi');
  } finally {
    if (mediaStream) {
      mediaStream.getTracks().forEach((track) => track.stop());
    }
    if (audioContext) {
      audioContext.close();
    }
    mediaStream = null;
    audioContext = null;
    workletNode = null;
    sourceNode = null;
    gainNode = null;
  }
}

function renderResponse(payload) {
  phraseEl.textContent = payload.phrase || '---';
  scoreEl.textContent = payload.score ?? '--';
  clarityEl.textContent = payload.indicators?.clarity ?? '--';
  centerednessEl.textContent = payload.indicators?.centeredness ?? '--';
  riskEl.textContent = payload.indicators?.risk ?? '--';
  transcriptEl.textContent = payload.meta?.transcript || '---';

  if (payload.active_silence?.enabled) {
    activeSilenceEl.textContent = payload.active_silence.phrase || '---';
  } else {
    activeSilenceEl.textContent = 'Non attivo';
  }

  alternativesEl.innerHTML = '';
  if (payload.alternatives && payload.alternatives.length > 0) {
    payload.alternatives.forEach((item) => {
      const li = document.createElement('li');
      li.textContent = item;
      alternativesEl.appendChild(li);
    });
  } else {
    const li = document.createElement('li');
    li.textContent = 'Disattivate o non disponibili.';
    alternativesEl.appendChild(li);
  }
}

function attachEvents() {
  modeSelect.addEventListener('change', updateStorage);
  liveBetaToggle.addEventListener('change', updateStorage);
  showAlternativesToggle.addEventListener('change', updateStorage);

  pttButton.addEventListener('pointerdown', startRecording);
  pttButton.addEventListener('pointerup', stopRecording);
  pttButton.addEventListener('pointerleave', stopRecording);
  pttButton.addEventListener('pointercancel', stopRecording);
}

async function init() {
  loadStorage();
  attachEvents();
  setStatus('Premi e parla');
}

init();
