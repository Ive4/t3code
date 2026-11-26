import { expect, it, vi } from "vite-plus/test";

import { Accelerometer } from "./expo-sensors.harmony.js";

const { bridge, events } = vi.hoisted(() => ({
  bridge: { startWatching: vi.fn(), stopWatching: vi.fn() },
  events: new Map(),
}));

vi.mock("react-native", () => ({
  TurboModuleRegistry: { get: () => bridge },
  DeviceEventEmitter: {
    addListener(event, listener) {
      events.set(event, listener);
      return { remove: () => events.delete(event) };
    },
  },
}));

it("keeps the preview usable when the platform cannot start the sensor", () => {
  bridge.startWatching.mockReturnValueOnce(false);
  const subscription = Accelerometer.addListener(() => {});
  try {
    expect(events.size).toBe(0);
  } finally {
    subscription.remove();
  }
});

it("normalizes a shake sample and stops delivering events when the preview closes", () => {
  bridge.startWatching.mockReturnValueOnce(true).mockReturnValueOnce(true);
  const firstSamples = [];
  Accelerometer.setUpdateInterval(50);
  const first = Accelerometer.addListener((sample) => firstSamples.push(sample));
  const [firstEvent, interval] = bridge.startWatching.mock.lastCall;
  try {
    expect(interval).toBe(50);
    events.get(firstEvent)({ x: 19.6133, y: 0, z: 0, timestamp: 2_500_000_000 });
    expect(firstSamples).toEqual([{ x: 2, y: 0, z: 0, timestamp: 2.5 }]);
  } finally {
    first.remove();
  }
  const nextSamples = [];
  const second = Accelerometer.addListener((sample) => nextSamples.push(sample));
  try {
    expect(events.has(firstEvent)).toBe(false);
    expect(bridge.stopWatching).toHaveBeenCalledTimes(1);
  } finally {
    second.remove();
  }
});
