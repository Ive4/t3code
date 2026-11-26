import { useSyncExternalStore } from "react";
import { DeviceEventEmitter, TurboModuleRegistry } from "react-native";

const native = () => TurboModuleRegistry.getEnforcing("T3Audio");
let nextId = 0;

const emptyPlayer = Object.freeze({
  isLoaded: false,
  isBuffering: false,
  playing: false,
  currentTime: 0,
  duration: 0,
  didJustFinish: false,
  error: null,
});

export function createAudioPlayer(source, options) {
  let uri = typeof source === "string" ? source : source?.uri;
  let current;
  let released = false;
  let status = emptyPlayer;
  const listeners = new Set();
  const publish = (next) => {
    status = next;
    for (const listener of listeners) listener();
  };
  const detach = () => {
    const previous = current;
    current = undefined;
    if (previous) {
      previous.subscription.remove();
      void native()
        .releasePlayer(previous.id)
        .catch(() => {});
    }
    publish(emptyPlayer);
  };
  const start = () => {
    if (current || !uri || released) return current;
    const id = ++nextId;
    const player = { id, requested: false };
    current = player;
    player.subscription = DeviceEventEmitter.addListener("T3AudioPlayer:" + id, (event) => {
      if (current !== player) return;
      const { state, positionMs, durationMs, buffering } = event;
      publish({
        isLoaded: ["prepared", "playing", "paused", "completed"].includes(state),
        isBuffering: buffering,
        playing: state === "playing",
        currentTime: Math.max(0, positionMs) / 1000,
        duration: Math.max(0, durationMs) / 1000,
        didJustFinish: state === "completed" && positionMs >= durationMs,
        error: state === "error" ? "Audio could not be played." : null,
      });
    });
    publish({ ...emptyPlayer, isBuffering: true });
    player.ready = native().preparePlayer(id, uri, options?.updateInterval ?? 500);
    player.pending = player.ready.catch(() => {});
    void player.ready.catch(() => {
      if (current === player) publish({ ...emptyPlayer, error: "Audio could not be played." });
    });
    return player;
  };
  const enqueue = (player, operation) => {
    const result = player.pending.then(async () => {
      if (current !== player) return;
      await player.ready;
      if (current === player) await operation();
    });
    player.pending = result.catch(() => {});
    return result;
  };

  return {
    getStatus: () => status,
    subscribe(listener) {
      listeners.add(listener);
      start();
      return () => listeners.delete(listener);
    },
    replace(source) {
      if (released) return;
      detach();
      uri = typeof source === "string" ? source : source?.uri;
      start();
    },
    play() {
      const player = start();
      if (!player) return;
      player.requested = true;
      void enqueue(player, async () => {
        if (player.requested) await native().playPlayer(player.id);
      }).catch(() => {
        if (current === player) publish({ ...emptyPlayer, error: "Audio could not be played." });
      });
    },
    pause() {
      const player = current;
      if (!player) return;
      player.requested = false;
      void enqueue(player, () => native().pausePlayer(player.id)).catch(() => {});
    },
    async seekTo(seconds) {
      const player = start();
      if (!player || !Number.isFinite(seconds)) throw new Error("Could not seek this audio.");
      await enqueue(player, () => native().seekPlayer(player.id, Math.round(seconds * 1000)));
    },
    release() {
      released = true;
      detach();
      listeners.clear();
    },
  };
}

export function useAudioPlayerStatus(player) {
  return useSyncExternalStore(player.subscribe, player.getStatus);
}

const emptyRecorder = Object.freeze({
  canRecord: false,
  isRecording: false,
  durationMillis: 0,
  metering: -160,
  isFinished: false,
  hasError: false,
  error: null,
  url: null,
});

class AudioRecorder {
  uri = null;
  #current;
  #status = emptyRecorder;
  #listeners = new Set();

  #publish(status) {
    this.#status = status;
    for (const listener of this.#listeners) listener(status);
  }

  async prepareToRecordAsync() {
    this.#detach();
    this.uri = null;
    this.#status = emptyRecorder;
    const id = ++nextId;
    const recording = { id };
    this.#current = recording;
    recording.subscription = DeviceEventEmitter.addListener("T3AudioRecorder:" + id, (status) => {
      if (this.#current === recording) this.#publish(status);
    });
    recording.ready = native().prepareRecorder(id);
    try {
      const uri = await recording.ready;
      if (this.#current === recording) {
        this.uri = uri;
        this.#status = { ...emptyRecorder, canRecord: true, url: uri };
      }
    } catch (error) {
      if (this.#current === recording) this.#detach();
      throw error;
    }
  }

  record({ forDuration }) {
    const recording = this.#current;
    if (!recording || !this.uri) throw new Error("Audio recorder is not prepared.");
    void native()
      .startRecorder(recording.id, forDuration)
      .catch(() => {
        if (this.#current === recording && !this.#status.hasError)
          this.#publish({
            ...emptyRecorder,
            hasError: true,
            error: "Could not start voice recording.",
            url: this.uri,
          });
      });
  }

  async stop() {
    const recording = this.#current;
    if (!recording) return;
    await recording.ready;
    if (this.#current === recording) await native().stopRecorder(recording.id);
  }

  getStatus() {
    return this.#status;
  }

  addListener(_eventName, listener) {
    this.#listeners.add(listener);
    return { remove: () => this.#listeners.delete(listener) };
  }

  getAvailableInputs() {
    return [];
  }

  setInput(_uid) {}

  release() {
    this.#detach();
    this.#listeners.clear();
  }

  #detach() {
    const recording = this.#current;
    this.#current = undefined;
    if (!recording) return;
    recording.subscription.remove();
    void native()
      .releaseRecorder(recording.id)
      .catch(() => {});
  }
}

export const AudioModule = Object.freeze({ AudioRecorder });
export const RecordingPresets = Object.freeze({
  HIGH_QUALITY: Object.freeze({
    extension: ".pcm",
    sampleRate: 16000,
    numberOfChannels: 1,
    bitRate: 256000,
  }),
});

export async function getRecordingPermissionsAsync() {
  return native().getRecordingPermission();
}

export async function requestRecordingPermissionsAsync() {
  return native().requestRecordingPermission();
}

// Shared audio-session ownership coordinates playback and recording on HarmonyOS.
export async function setAudioModeAsync() {}
export async function setIsAudioActiveAsync() {}
