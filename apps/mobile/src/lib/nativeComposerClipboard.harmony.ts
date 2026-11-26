import { encodeComposerContextClipboardHtml } from "@t3tools/shared/composerContextClipboard";
import { TurboModuleRegistry, type TurboModule } from "react-native";

interface ComposerClipboard extends TurboModule {
  writeComposerClipboard(text: string, html: string): Promise<void>;
}

export function writeNativeComposerClipboard(text: string, fragment: string): Promise<void> {
  return TurboModuleRegistry.getEnforcing<ComposerClipboard>(
    "T3Interaction",
  ).writeComposerClipboard(text, encodeComposerContextClipboardHtml(text, fragment));
}
