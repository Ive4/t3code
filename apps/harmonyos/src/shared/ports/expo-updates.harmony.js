export const isEnabled = false;

async function unavailable() {
  throw new Error("EAS Updates is unavailable on HarmonyOS.");
}

export const checkForUpdateAsync = unavailable;
export const fetchUpdateAsync = unavailable;
export const reloadAsync = unavailable;
export const readLogEntriesAsync = unavailable;
