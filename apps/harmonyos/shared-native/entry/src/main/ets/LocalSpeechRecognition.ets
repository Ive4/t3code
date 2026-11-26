import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { speechRecognizer } from '@kit.CoreSpeechKit';

export const LOCAL_SPEECH_LIMIT_SECONDS = 60;
const FRAME_BYTES = 1280;
const FRAME_MILLISECONDS = 40;
const MAX_PCM_BYTES = 16000 * 2 * LOCAL_SPEECH_LIMIT_SECONDS;

export interface SpeechRecording {
  bytes: number;
  finished: boolean;
  failed: boolean;
}

export class LocalSpeechRecognition {
  readonly id: string;
  private readonly path: string;
  private readonly recording: SpeechRecording | undefined;
  private readonly buffer = new ArrayBuffer(FRAME_BYTES);
  private readonly segments: string[] = [];
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined;
  private settle: ((error?: Error) => void) | undefined;
  private cancellation: Error | undefined;
  private timer = -1;
  private timeout = -1;
  private size = 0;
  private offset = 0;
  private started = false;
  private finishing = false;
  private completed = false;

  constructor(id: string, path: string, recording: SpeechRecording | undefined) {
    this.id = id;
    this.path = path;
    this.recording = recording;
  }

  public async transcribe(): Promise<string> {
    const file = fileIo.openSync(this.path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(file.fd);
      if (!stat.isFile() || stat.size > MAX_PCM_BYTES || stat.size % 2 !== 0 ||
        (!this.recording && stat.size === 0)) {
        throw new Error('Invalid local speech recording.');
      }
      this.size = stat.size;
      return await new Promise<string>((resolve, reject) => {
        this.settle = (error?: Error) => {
          if (error) reject(error);
          else resolve(this.segments.join(''));
        };
        this.setTimeout(15000);
        void this.startEngine(file).catch((error: BusinessError) => {
          this.complete(new Error(`Could not start offline speech recognition (${error.code}).`));
        });
      });
    } finally {
      try {
        fileIo.closeSync(file);
      } finally {
        this.releaseEngine();
      }
    }
  }

  public cancel(): void {
    if (!this.settle) return;
    const error = new Error('Offline speech recognition was cancelled.');
    if (this.engine) this.complete(error);
    else this.cancellation = error;
  }

  private async startEngine(file: fileIo.File): Promise<void> {
    const engine = await speechRecognizer.createEngine({
      language: 'zh-CN',
      online: 1,
      extraParams: { 'locate': 'CN', 'recognizerMode': 'long' },
    });
    if (!this.settle || this.cancellation) {
      try {
        engine.shutdown();
      } finally {
        if (this.cancellation) this.complete(this.cancellation);
      }
      return;
    }
    this.engine = engine;
    engine.setListener({
      onStart: (id: string) => {
        if (id !== this.id || !this.settle || this.started) return;
        this.started = true;
        this.setTimeout(LOCAL_SPEECH_LIMIT_SECONDS * 1000 + 15000);
        this.sendFrame(engine, file);
      },
      onEvent: () => {},
      onResult: (id: string, result: speechRecognizer.SpeechRecognitionResult) => {
        if (id === this.id && this.settle && result.isFinal) this.segments.push(result.result);
      },
      onComplete: (id: string) => {
        if (id !== this.id || !this.settle) return;
        if (!this.finishing) {
          this.complete(new Error('Offline speech recognition did not process the complete recording.'));
          return;
        }
        this.completed = true;
        this.complete();
      },
      onError: (id: string, code: number) => {
        if (id === this.id) this.complete(new Error(`Offline speech recognition failed (${code}).`));
      },
    });
    engine.startListening({
      sessionId: this.id,
      audioInfo: { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 },
      extraParams: { 'recognitionMode': 1, 'maxAudioDuration': LOCAL_SPEECH_LIMIT_SECONDS * 1000 + 1000 },
    });
  }

  private sendFrame(engine: speechRecognizer.SpeechRecognitionEngine, file: fileIo.File): void {
    if (!this.settle) return;
    const size = this.recording?.bytes ?? this.size;
    const finished = this.recording?.finished ?? true;
    if (this.recording?.failed || size > MAX_PCM_BYTES || (finished && size === 0)) {
      this.complete(new Error('Invalid local speech recording.'));
      return;
    }
    const remaining = size - this.offset;
    try {
      if (finished && remaining === 0) {
        this.finishing = true;
        this.setTimeout(10000);
        engine.finish(this.id);
        return;
      }
      this.timer = setTimeout(() => this.sendFrame(engine, file), FRAME_MILLISECONDS);
      if (finished || remaining >= FRAME_BYTES) {
        const length = Math.min(remaining, FRAME_BYTES);
        const read = fileIo.readSync(file.fd, this.buffer, { length });
        if (read !== length) throw new Error('Could not read the local speech recording.');
        const bytes = new Uint8Array(this.buffer);
        bytes.fill(0, length);
        this.offset += length;
        engine.writeAudio(this.id, bytes);
      }
    } catch (cause) {
      this.complete(new Error('Could not stream the complete recording to offline speech recognition.'));
    }
  }

  private setTimeout(milliseconds: number): void {
    if (this.timeout !== -1) clearTimeout(this.timeout);
    this.timeout = setTimeout(() => {
      this.complete(new Error('Offline speech recognition timed out.'));
    }, milliseconds);
  }

  private complete(error?: Error): void {
    const settle = this.settle;
    this.settle = undefined;
    if (this.timer !== -1) clearTimeout(this.timer);
    if (this.timeout !== -1) clearTimeout(this.timeout);
    settle?.(error);
  }

  private releaseEngine(): void {
    const engine = this.engine;
    this.engine = undefined;
    if (!engine) return;
    if (!this.completed) {
      try {
        engine.cancel(this.id);
      } catch (cause) {}
    }
    try {
      engine.shutdown();
    } catch (cause) {}
  }
}
