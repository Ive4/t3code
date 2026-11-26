import type { T3Highlights } from "@t3tools/mobile-highlights-native";
import { NitroModules } from "react-native-nitro-modules";

export const nativeHighlights = NitroModules.hasHybridObject("T3Highlights")
  ? NitroModules.createHybridObject<T3Highlights>("T3Highlights")
  : undefined;
