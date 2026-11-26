import { abilityAccessCtrl, bundleManager } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { http } from '@kit.NetworkKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';
import { LOCAL_SPEECH_LIMIT_SECONDS, LocalSpeechRecognition, SpeechRecording } from './LocalSpeechRecognition';

const MICROPHONE = 'ohos.permission.MICROPHONE';
const PCM_RATE = 16000;
const PCM_BYTES_PER_SECOND = PCM_RATE * 2;
const MAX_RECORDING_SECONDS = 5 * 60;
const CANCELLED = 'Audio operation was cancelled.';
const PLAYBACK_ERROR = 'Audio could not be played.';
const RECORDING_ERROR = 'Could not record audio.';
const MAX_SPEECH_REQUEST_BYTES = PCM_BYTES_PER_SECOND * MAX_RECORDING_SECONDS * 2 + 128004;

interface SpeechResponse {
  status: number;
  body: string;
  headers: string;
}

interface Permission {
  granted: boolean;
  status: string;
  canAskAgain: boolean;
  expires: string;
}

interface PlayerStatus {
  state: string;
  positionMs: number;
  durationMs: number;
  buffering: boolean;
}

interface RecorderStatus {
  canRecord: boolean;
  isRecording: boolean;
  durationMillis: number;
  metering: number;
  isFinished: boolean;
  hasError: boolean;
  error: string | null;
  url: string;
}

class Player {
  native: media.AVPlayer | undefined;
  file: fileIo.File | undefined;
  buffer = false;
  positionMs = 0;
  durationMs = 0;
  lastProgressAt = 0;
  initialized: ((error?: Error) => void) | undefined;
  seeked: ((error?: Error) => void) | undefined;
}

class Recorder implements SpeechRecording {
  readonly id: number;
  readonly path: string;
  readonly uri: string;
  native: audio.AudioCapturer | undefined;
  file: fileIo.File | undefined;
  bytes = 0;
  limit = 0;
  maxSeconds = MAX_RECORDING_SECONDS;
  finished = false;
  acceptingData = false;
  failed = false;
  lastProgressAt = 0;
  maximum = 0;
  timer = -1;

  constructor(id: number, path: string) {
    this.id = id;
    this.path = path;
    this.uri = 'file://' + path.split('/').map((part: string) => encodeURIComponent(part)).join('/');
  }
}

export class AudioModule extends UITurboModule {
  private readonly players = new Map<number, Player>();
  private readonly speechRequests = new Map<string, http.HttpRequest>();
  private localSpeech: LocalSpeechRecognition | undefined;
  private recorder: Recorder | undefined;
  private recorderTransition: Promise<void> = Promise.resolve();
  private destroyed = false;
  private microphoneRequested = false;
  private microphoneCanAskAgain = true;

  public async preparePlayer(id: number, uri: string, intervalMs: number): Promise<void> {
    if (this.destroyed || this.players.has(id)) throw new Error(CANCELLED);
    const player = new Player();
    this.players.set(id, player);
    try {
      const native = await media.createAVPlayer();
      if (this.players.get(id) !== player) {
        await native.release();
        throw new Error(CANCELLED);
      }
      player.native = native;
      const progressInterval = Math.max(100, Math.min(1000, intervalMs));
      native.on('stateChange', (state: media.AVPlayerState) => {
        if (state === 'initialized') player.initialized?.();
        if (state === 'error') this.playerError(id, player);
        else if (state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed') {
          if (state === 'prepared') player.durationMs = native.duration;
          if (state === 'completed') player.positionMs = player.durationMs;
          this.emitPlayer(id, player, state);
        }
      });
      native.on('error', () => this.playerError(id, player));
      native.on('timeUpdate', (position: number) => {
        if (player.seeked) return;
        player.positionMs = position;
        if (native.state !== 'playing' || Date.now() - player.lastProgressAt < progressInterval) return;
        player.lastProgressAt = Date.now();
        this.emitPlayer(id, player, native.state);
      });
      native.on('seekDone', (position: number) => {
        player.positionMs = position;
        player.seeked?.();
        this.emitPlayer(id, player, native.state);
      });
      native.on('bufferingUpdate', (type: media.BufferingInfoType) => {
        if (type !== media.BufferingInfoType.BUFFERING_START &&
          type !== media.BufferingInfoType.BUFFERING_END) return;
        player.buffer = type === media.BufferingInfoType.BUFFERING_START;
        this.emitPlayer(id, player, native.state);
      });

      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => player.initialized?.(new Error(PLAYBACK_ERROR)), 15000);
        player.initialized = (error?: Error) => {
          clearTimeout(timer);
          player.initialized = undefined;
          if (error) reject(error);
          else resolve();
        };
        try {
          if (/^https?:\/\/[^/\s?#]+/i.test(uri)) {
            native.url = uri;
          } else {
            player.file = fileIo.openSync(this.playbackPath(uri), fileIo.OpenMode.READ_ONLY);
            const stat = fileIo.statSync(player.file.fd);
            if (!stat.isFile() || stat.size === 0) throw new Error(PLAYBACK_ERROR);
            native.fdSrc = { fd: player.file.fd, offset: 0, length: stat.size };
          }
        } catch (cause) {
          player.initialized?.(new Error(PLAYBACK_ERROR));
        }
      });
      if (this.players.get(id) !== player) throw new Error(CANCELLED);
      await native.prepare();
    } catch (cause) {
      await this.releasePlayer(id).catch(() => {});
      throw new Error(PLAYBACK_ERROR);
    }
  }

  public async playPlayer(id: number): Promise<void> {
    const native = this.players.get(id)?.native;
    if (native && native.state !== 'playing') await native.play();
  }

  public async pausePlayer(id: number): Promise<void> {
    const native = this.players.get(id)?.native;
    if (native?.state === 'playing') await native.pause();
  }

  public async seekPlayer(id: number, positionMs: number): Promise<void> {
    const player = this.players.get(id);
    const native = player?.native;
    if (!player || !native || player.seeked || !Number.isFinite(positionMs)) {
      throw new Error('Could not seek this audio.');
    }
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => player.seeked?.(new Error('Could not seek this audio.')), 5000);
      player.seeked = (error?: Error) => {
        clearTimeout(timer);
        player.seeked = undefined;
        if (error) reject(error);
        else resolve();
      };
      try {
        native.seek(Math.round(Math.max(0, Math.min(native.duration, positionMs))));
      } catch (cause) {
        player.seeked?.(new Error('Could not seek this audio.'));
      }
    });
  }

  public async releasePlayer(id: number): Promise<void> {
    const player = this.players.get(id);
    if (!player) return;
    this.players.delete(id);
    player.initialized?.(new Error(CANCELLED));
    player.seeked?.(new Error(CANCELLED));
    try {
      await player.native?.release();
    } finally {
      if (player.file) fileIo.closeSync(player.file);
    }
  }

  public async getRecordingPermission(): Promise<Permission> {
    const bundle = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    const granted = abilityAccessCtrl.createAtManager().checkAccessTokenSync(
      bundle.appInfo.accessTokenId, MICROPHONE,
    ) === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    return {
      granted,
      status: granted ? 'granted' : (this.microphoneRequested ? 'denied' : 'undetermined'),
      canAskAgain: granted || this.microphoneCanAskAgain,
      expires: 'never',
    };
  }

  public async requestRecordingPermission(): Promise<Permission> {
    const current = await this.getRecordingPermission();
    if (!current.granted) {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
        this.ctx.uiAbilityContext, [MICROPHONE],
      );
      this.microphoneRequested = true;
      this.microphoneCanAskAgain = result.dialogShownResults?.[0] === true;
    }
    return this.getRecordingPermission();
  }

  public async prepareRecorder(id: number): Promise<string> {
    let uri = '';
    await this.enqueueRecorder(async () => {
      if (this.destroyed) throw new Error(CANCELLED);
      if (this.recorder) await this.finishRecorder(this.recorder, false);
      const path = this.ctx.uiAbilityContext.cacheDir + '/t3-recording-' + util.generateRandomUUID() + '.pcm';
      const recorder = new Recorder(id, path);
      this.recorder = recorder;
      try {
        const native = await audio.createAudioCapturer({
          streamInfo: {
            samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
            channels: audio.AudioChannel.CHANNEL_1,
            sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
            encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
          },
          capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 },
        });
        recorder.native = native;
        if (this.destroyed) throw new Error(CANCELLED);
        recorder.file = fileIo.openSync(path, fileIo.OpenMode.CREATE |
          fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
        native.on('readData', (buffer: ArrayBuffer) => this.capture(recorder, buffer));
        native.on('stateChange', (state: audio.AudioState) => {
          if (recorder.acceptingData && (state === audio.AudioState.STATE_STOPPED ||
            state === audio.AudioState.STATE_PAUSED)) this.recordingFailed(recorder);
        });
        uri = recorder.uri;
      } catch (cause) {
        await this.finishRecorder(recorder, false);
        throw new Error(RECORDING_ERROR);
      }
    });
    return uri;
  }

  public async startRecorder(id: number, durationSeconds: number): Promise<void> {
    await this.enqueueRecorder(async () => {
      const recorder = this.recorder;
      if (this.destroyed || !recorder || recorder.id !== id || !recorder.native ||
        recorder.acceptingData || !Number.isFinite(durationSeconds) || durationSeconds <= 0) {
        throw new Error(RECORDING_ERROR);
      }
      const seconds = Math.min(durationSeconds, recorder.maxSeconds);
      recorder.limit = Math.floor(seconds * PCM_RATE) * 2;
      try {
        await recorder.native.start();
        recorder.acceptingData = true;
        recorder.timer = setTimeout(() => {
          void this.stopRecorder(id).catch(() => {});
        }, Math.ceil(seconds * 1000));
        this.emitRecorder(recorder);
      } catch (cause) {
        await this.finishRecorder(recorder, false);
        throw new Error(RECORDING_ERROR);
      }
    });
  }

  public async stopRecorder(id: number): Promise<void> {
    await this.enqueueRecorder(async () => {
      const recorder = this.recorder;
      if (!recorder || recorder.id !== id) return;
      await this.finishRecorder(recorder, recorder.bytes > 0 && !recorder.failed);
      this.emitRecorder(recorder);
      if (recorder.failed) throw new Error(RECORDING_ERROR);
    });
  }

  public async releaseRecorder(id: number): Promise<void> {
    await this.enqueueRecorder(async () => {
      const recorder = this.recorder;
      if (recorder?.id === id) await this.finishRecorder(recorder, false);
    });
  }

  public async requestSpeech(
    id: string, url: string, method: string, headers: string, bodyUri: string,
  ): Promise<SpeechResponse> {
    if (this.destroyed || this.speechRequests.has(id) ||
      !/^[0-9a-f-]{36}$/i.test(id) || !/^https?:\/\/[^/\s?#]+/i.test(url)) {
      throw new Error('Invalid speech request.');
    }
    let requestMethod: http.RequestMethod;
    switch (method) {
      case 'GET': requestMethod = http.RequestMethod.GET; break;
      case 'POST': requestMethod = http.RequestMethod.POST; break;
      case 'DELETE': requestMethod = http.RequestMethod.DELETE; break;
      default: throw new Error('Unsupported speech request method.');
    }
    const request = http.createHttp();
    this.speechRequests.set(id, request);
    try {
      const options: http.HttpRequestOptions = {
        method: requestMethod,
        header: JSON.parse(headers) as Object,
        expectDataType: http.HttpDataType.STRING,
        maxRedirects: 0,
        maxLimit: 4 * 1024 * 1024,
        usingCache: false,
        readTimeout: 30 * 60 * 1000,
      };
      if (bodyUri !== '') {
        const path = this.playbackPath(bodyUri);
        if (path !== this.ctx.uiAbilityContext.cacheDir + '/t3-speech-send-' + id) {
          throw new Error('Invalid speech request body.');
        }
        options.extraData = await this.readSpeechRequest(path);
      }
      if (this.speechRequests.get(id) !== request) throw new Error(CANCELLED);
      const response = await request.request(url, options);
      if (this.speechRequests.get(id) !== request) throw new Error(CANCELLED);
      return {
        status: response.responseCode,
        body: typeof response.result === 'string' ? response.result : JSON.stringify(response.result),
        headers: typeof response.header === 'string' ? response.header : JSON.stringify(response.header),
      };
    } finally {
      await this.cancelSpeech(id);
    }
  }

  public async cancelSpeech(id: string): Promise<void> {
    const request = this.speechRequests.get(id);
    if (!request) return;
    this.speechRequests.delete(id);
    request.destroy();
  }

  public async checkLocalSpeechAvailability(): Promise<boolean> {
    return !this.destroyed && canIUse('SystemCapability.AI.SpeechRecognizer');
  }

  public async transcribeLocalSpeech(id: string, uri: string): Promise<string> {
    if (this.destroyed || this.localSpeech || !/^[0-9a-f-]{36}$/i.test(id) ||
      !canIUse('SystemCapability.AI.SpeechRecognizer')) {
      throw new Error('Offline speech recognition is unavailable.');
    }
    const path = this.playbackPath(uri);
    const cache = this.ctx.uiAbilityContext.cacheDir + '/';
    if (!path.startsWith(cache) || !/^t3-recording-[0-9a-f-]+\.pcm$/i.test(path.slice(cache.length))) {
      throw new Error('Invalid local speech recording.');
    }
    const recorder = this.recorder?.path === path ? this.recorder : undefined;
    if (recorder) recorder.maxSeconds = LOCAL_SPEECH_LIMIT_SECONDS;
    const operation = new LocalSpeechRecognition(id, path, recorder);
    this.localSpeech = operation;
    try {
      return await operation.transcribe();
    } finally {
      this.localSpeech = undefined;
    }
  }

  public async cancelLocalSpeech(id: string): Promise<void> {
    if (this.localSpeech?.id === id) this.localSpeech.cancel();
  }

  public override __onDestroy__(): void {
    this.destroyed = true;
    this.localSpeech?.cancel();
    for (const id of this.players.keys()) void this.releasePlayer(id).catch(() => {});
    for (const id of this.speechRequests.keys()) void this.cancelSpeech(id).catch(() => {});
    void this.enqueueRecorder(async () => {
      if (this.recorder) await this.finishRecorder(this.recorder, false);
    }).catch(() => {});
  }

  private async readSpeechRequest(path: string): Promise<ArrayBuffer> {
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(file.fd);
      if (!stat.isFile() || stat.size === 0 || stat.size > MAX_SPEECH_REQUEST_BYTES) {
        throw new Error('Invalid speech request body.');
      }
      const body = new Uint8Array(stat.size);
      const buffer = new ArrayBuffer(64 * 1024);
      let offset = 0;
      while (offset < body.length) {
        const length = await fileIo.read(file.fd, buffer, { length: Math.min(buffer.byteLength, body.length - offset) });
        if (length <= 0) throw new Error('Could not read the speech request.');
        body.set(new Uint8Array(buffer, 0, length), offset);
        offset += length;
      }
      return body.buffer;
    } finally {
      await fileIo.close(file);
    }
  }

  private playbackPath(uri: string): string {
    const encoded = /^file:\/\/\/([^?#]+)$/.exec(uri)?.[1];
    if (!encoded) throw new Error(PLAYBACK_ERROR);
    const segments = encoded.split('/').map((part: string) => decodeURIComponent(part));
    if (segments.some((part: string) => !part || part === '.' || part === '..' || /[\/\\\x00]/.test(part))) {
      throw new Error(PLAYBACK_ERROR);
    }
    const path = '/' + segments.join('/');
    const context = this.ctx.uiAbilityContext;
    const root = [context.filesDir, context.cacheDir].find((candidate: string) => path.startsWith(candidate + '/'));
    if (!root) throw new Error(PLAYBACK_ERROR);
    let part = root;
    for (const segment of path.slice(root.length + 1).split('/')) {
      part += '/' + segment;
      const stat = fileIo.lstatSync(part);
      if (part === path ? !stat.isFile() : !stat.isDirectory()) throw new Error(PLAYBACK_ERROR);
    }
    return path;
  }

  private emitPlayer(id: number, player: Player, state: media.AVPlayerState): void {
    if (this.players.get(id) !== player) return;
    const status: PlayerStatus = {
      state,
      positionMs: player.positionMs,
      durationMs: player.durationMs,
      buffering: player.buffer || state === 'idle' || state === 'initialized',
    };
    this.ctx.rnInstance.emitDeviceEvent('T3AudioPlayer:' + id, status);
  }

  private playerError(id: number, player: Player): void {
    player.initialized?.(new Error(PLAYBACK_ERROR));
    player.seeked?.(new Error(PLAYBACK_ERROR));
    this.emitPlayer(id, player, 'error');
    void this.releasePlayer(id).catch(() => {});
  }

  private enqueueRecorder(operation: () => Promise<void>): Promise<void> {
    const result = this.recorderTransition.then(operation);
    this.recorderTransition = result.catch(() => {});
    return result;
  }

  private capture(recorder: Recorder, buffer: ArrayBuffer): void {
    const file = recorder.file;
    if (!file || !recorder.acceptingData || recorder.failed) return;
    const length = Math.min(buffer.byteLength - buffer.byteLength % 2, recorder.limit - recorder.bytes);
    if (length <= 0) return;
    try {
      const written = fileIo.writeSync(file.fd, buffer, { length });
      if (written !== length) throw new Error(RECORDING_ERROR);
      recorder.bytes += written;
      const samples = new Int16Array(buffer, 0, length / 2);
      for (let index = 0; index < samples.length; index++) {
        recorder.maximum = Math.max(recorder.maximum, Math.abs(samples[index]));
      }
      if (Date.now() - recorder.lastProgressAt >= 100) {
        recorder.lastProgressAt = Date.now();
        this.emitRecorder(recorder);
        recorder.maximum = 0;
      }
    } catch (cause) {
      this.recordingFailed(recorder);
    }
  }

  private recordingFailed(recorder: Recorder): void {
    if (recorder.failed) return;
    recorder.failed = true;
    void this.stopRecorder(recorder.id).catch(() => {});
  }

  private emitRecorder(recorder: Recorder): void {
    if (this.destroyed) return;
    const status: RecorderStatus = {
      canRecord: !recorder.finished,
      isRecording: recorder.acceptingData,
      durationMillis: Math.round(recorder.bytes * 1000 / PCM_BYTES_PER_SECOND),
      metering: 20 * Math.log10(Math.max(recorder.maximum, 1) / 32768),
      isFinished: recorder.finished,
      hasError: recorder.failed,
      error: recorder.failed ? RECORDING_ERROR : null,
      url: recorder.uri,
    };
    this.ctx.rnInstance.emitDeviceEvent('T3AudioRecorder:' + recorder.id, status);
  }

  private async finishRecorder(recorder: Recorder, keep: boolean): Promise<void> {
    this.recorder = undefined;
    recorder.acceptingData = false;
    recorder.finished = true;
    if (recorder.timer !== -1) clearTimeout(recorder.timer);
    const native = recorder.native;
    try {
      if (native?.state === audio.AudioState.STATE_RUNNING) await native.stop();
    } catch (cause) {
      recorder.failed = true;
    }
    try {
      await native?.release();
    } catch (cause) {
      recorder.failed = true;
    }
    if (recorder.file) {
      try {
        fileIo.closeSync(recorder.file);
      } catch (cause) {
        recorder.failed = true;
      }
      if (!keep || recorder.failed) {
        try {
          fileIo.unlinkSync(recorder.path);
        } catch (cause) {}
      }
    }
  }
}
