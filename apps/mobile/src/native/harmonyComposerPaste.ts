import { decodeComposerContextClipboardHtml } from "@t3tools/shared/composerContextClipboard";
import { hasThreadLinks } from "@t3tools/shared/threadLinks";

export interface HarmonyComposerClipboard {
  readonly text: string;
  readonly html: string;
  readonly uris: ReadonlyArray<string>;
  readonly imageToken?: string;
}

export function harmonyComposerPaste({ text, html, uris }: HarmonyComposerClipboard) {
  if (decodeComposerContextClipboardHtml(html)) return { kind: "context", text, html } as const;
  if (uris.length > 0) return { kind: "images", uris } as const;
  if (text.length === 0) return null;
  if (hasThreadLinks(text)) return { kind: "context", text, html: "" } as const;
  return { kind: "text", text } as const;
}

type Paste = NonNullable<ReturnType<typeof harmonyComposerPaste>>;

export async function deliverHarmonyComposerPaste(
  data: HarmonyComposerClipboard,
  signal: AbortSignal,
  handlers: {
    readonly takeImages: (token: string, materialize: boolean) => Promise<ReadonlyArray<string>>;
    readonly releaseImage: (uri: string) => Promise<void>;
    readonly deliver: (paste: Paste) => void | Promise<void>;
  },
): Promise<void> {
  const paste = harmonyComposerPaste(data);
  const images = data.imageToken
    ? await handlers.takeImages(data.imageToken, !signal.aborted && paste?.kind !== "context")
    : [];
  try {
    if (signal.aborted) return;
    if (images.length > 0) {
      await handlers.deliver({ kind: "images", uris: [...data.uris, ...images] });
    } else if (paste) {
      await handlers.deliver(paste);
    }
  } finally {
    await Promise.all(images.map((uri) => handlers.releaseImage(uri)));
  }
}
