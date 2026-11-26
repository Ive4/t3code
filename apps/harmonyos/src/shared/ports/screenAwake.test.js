import { expect, it, vi } from "vite-plus/test";

import { activateKeepAwakeAsync, deactivateKeepAwake } from "./expo-keep-awake.harmony.js";

const { bridge } = vi.hoisted(() => ({ bridge: { setKeepScreenOn: vi.fn() } }));

vi.mock("react-native", () => ({
  TurboModuleRegistry: { get: () => bridge },
}));

it("keeps the screen on until all active recording tags have been released", async () => {
  const started = Promise.withResolvers();
  const allowActivation = Promise.withResolvers();
  const transitions = [];
  bridge.setKeepScreenOn.mockImplementation(async (awake) => {
    if (awake) {
      started.resolve();
      await allowActivation.promise;
    }
    transitions.push(awake);
  });

  const first = activateKeepAwakeAsync("voice-input:1");
  const second = activateKeepAwakeAsync("voice-input:2");
  const firstReleased = deactivateKeepAwake("voice-input:1");
  await started.promise;
  allowActivation.resolve();
  await Promise.all([first, second, firstReleased]);
  try {
    expect(transitions).toEqual([true]);
  } finally {
    await deactivateKeepAwake("voice-input:2");
  }
  expect(transitions).toEqual([true, false]);
});

it("can acquire a wake lock after the previous activation failed", async () => {
  bridge.setKeepScreenOn.mockRejectedValueOnce(new Error("Window unavailable"));
  await expect(activateKeepAwakeAsync("voice-input:3")).rejects.toThrow("Window unavailable");
  await activateKeepAwakeAsync("voice-input:4");
  await deactivateKeepAwake("voice-input:4");
  expect(bridge.setKeepScreenOn).toHaveBeenLastCalledWith(false);
});
