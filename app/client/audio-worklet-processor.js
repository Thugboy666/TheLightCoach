class PCMWorkletProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.inputSampleRate = sampleRate;
    this.targetSampleRate = 16000;
    this._buffer = [];
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || !input[0]) {
      return true;
    }
    const channel = input[0];
    const downsampled = this.downsample(channel, this.inputSampleRate, this.targetSampleRate);
    const pcm16 = this.floatTo16BitPCM(downsampled);
    this.port.postMessage(pcm16.buffer, [pcm16.buffer]);
    return true;
  }

  downsample(buffer, inRate, outRate) {
    if (outRate === inRate) {
      return buffer;
    }
    const ratio = inRate / outRate;
    const newLength = Math.round(buffer.length / ratio);
    const result = new Float32Array(newLength);
    let offsetResult = 0;
    let offsetBuffer = 0;
    while (offsetResult < result.length) {
      const nextOffsetBuffer = Math.round((offsetResult + 1) * ratio);
      let accum = 0;
      let count = 0;
      for (let i = offsetBuffer; i < nextOffsetBuffer && i < buffer.length; i += 1) {
        accum += buffer[i];
        count += 1;
      }
      result[offsetResult] = accum / count;
      offsetResult += 1;
      offsetBuffer = nextOffsetBuffer;
    }
    return result;
  }

  floatTo16BitPCM(floatBuffer) {
    const output = new Int16Array(floatBuffer.length);
    for (let i = 0; i < floatBuffer.length; i += 1) {
      const s = Math.max(-1, Math.min(1, floatBuffer[i]));
      output[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
    }
    return output;
  }
}

registerProcessor('pcm-worklet', PCMWorkletProcessor);
