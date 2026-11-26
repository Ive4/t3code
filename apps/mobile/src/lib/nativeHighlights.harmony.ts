import type { T3Highlights } from "@t3tools/mobile-highlights-native";

// Importing NitroModules throws on Harmony. The shared tokenizer handles its absence.
export const nativeHighlights: T3Highlights | undefined = undefined;
