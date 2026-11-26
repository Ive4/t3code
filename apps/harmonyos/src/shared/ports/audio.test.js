import { expect, it, vi } from "vite-plus/test";

import { AudioModule, createAudioPlayer } from "./expo-audio.harmony.js";

const { bridge, events } = vi.hoisted(() => ({
  bridge: {
    preparePlayer: vi.fn(),
    playPlayer: vi.fn(),
    pausePlayer: vi.fn(),
    releasePlayer: vi.fn(),
    prepareRecorder: vi.fn(),
    startRecorder: vi.fn(),
    stopRecorder: vi.fn(),
    releaseRecorder: vi.fn(),
  },
  events: new Map(),
}));

vi.mock("react-native", () => ({
  TurboModuleRegistry: { getEnforcing: () => bridge },
  DeviceEventEmitter: {
    addListener(name, callback) {
      events.set(name, callback);
      return { remove: () => events.delete(name) };
    },
  },
}));

it("drops a play request paused while an inline attachment is still loading", async () => {
  bridge.releasePlayer.mockResolvedValue(undefined);
  const paused = Promise.withResolvers();
  bridge.pausePlayer.mockImplementationOnce(() => {
    paused.resolve();
    return Promise.resolve();
  });
  const ready = Promise.withResolvers();
  bridge.preparePlayer.mockReturnValueOnce(ready.promise);
  const player = createAudioPlayer(null, { updateInterval: 500 });
  player.replace({ uri: "file:///cache/attachment.m4a" });
  player.play();
  player.pause();

  const [id] = bridge.preparePlayer.mock.lastCall;
  const receiveStatus = events.get("T3AudioPlayer:" + id);
  receiveStatus({ state: "prepared", positionMs: 0, durationMs: 5100, buffering: false });
  ready.resolve();
  await paused.promise;
  expect(player.getStatus()).toMatchObject({ isLoaded: true, playing: false, duration: 5.1 });
  expect(bridge.playPlayer).not.toHaveBeenCalled();
  player.release();
  receiveStatus({ state: "playing", positionMs: 500, durationMs: 5100, buffering: false });
  expect(player.getStatus()).toMatchObject({ isLoaded: false, playing: false });
});

it("retains a recording URI through stop and ignores events from a previous recording", async () => {
  bridge.releaseRecorder.mockResolvedValue(undefined);
  bridge.startRecorder.mockResolvedValue(undefined);
  bridge.stopRecorder.mockResolvedValue(undefined);
  const recorder = new AudioModule.AudioRecorder();
  bridge.prepareRecorder.mockResolvedValueOnce("file:///cache/first.pcm");
  await recorder.prepareToRecordAsync();
  const [firstId] = bridge.prepareRecorder.mock.lastCall;
  const previousEvent = events.get("T3AudioRecorder:" + firstId);
  recorder.record({ forDuration: 10 });
  await recorder.stop();
  expect(recorder.uri).toBe("file:///cache/first.pcm");

  bridge.prepareRecorder.mockResolvedValueOnce("file:///cache/second.pcm");
  await recorder.prepareToRecordAsync();
  previousEvent({ isFinished: true, hasError: false, durationMillis: 500, url: recorder.uri });
  expect(recorder.getStatus()).toMatchObject({ canRecord: true, durationMillis: 0 });
  recorder.release();
});
