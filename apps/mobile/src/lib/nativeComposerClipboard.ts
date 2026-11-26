import { requireNativeModule } from "expo";

export function writeNativeComposerClipboard(text: string, fragment: string): Promise<void> {
  return requireNativeModule<{
    writeContextClipboard: (text: string, fragment: string) => Promise<void>;
  }>("T3ComposerEditor").writeContextClipboard(text, fragment);
}
