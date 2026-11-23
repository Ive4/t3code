import { File } from "expo-file-system";

export async function fetch(input, init) {
  if (typeof input === "string" && input.startsWith("file://")) {
    if (init?.signal?.aborted) throw init.signal.reason;
    const bytes = await new File(input).bytes();
    if (init?.signal?.aborted) throw init.signal.reason;
    return new Response(bytes);
  }
  return globalThis.fetch(input, init);
}
