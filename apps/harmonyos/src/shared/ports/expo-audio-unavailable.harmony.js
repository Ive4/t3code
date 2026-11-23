function audioUnavailable() {
  return Object.assign(new Error("Audio is unavailable on HarmonyOS."), {
    code: "ERR_UNAVAILABLE",
  });
}

function UnavailableAudioRecorder() {
  throw audioUnavailable();
}

export const AudioModule = Object.freeze({ AudioRecorder: UnavailableAudioRecorder });
export const RecordingPresets = Object.freeze({
  HIGH_QUALITY: Object.freeze({
    extension: ".m4a",
    sampleRate: 44100,
    numberOfChannels: 2,
    bitRate: 128000,
  }),
});

export async function getRecordingPermissionsAsync() {
  return { status: "denied", granted: false, canAskAgain: false, expires: "never" };
}
export const requestRecordingPermissionsAsync = getRecordingPermissionsAsync;

export async function setAudioModeAsync() {
  throw audioUnavailable();
}
export async function setIsAudioActiveAsync() {
  throw audioUnavailable();
}
export function createAudioPlayer() {
  throw audioUnavailable();
}
export function useAudioPlayerStatus() {
  throw audioUnavailable();
}
