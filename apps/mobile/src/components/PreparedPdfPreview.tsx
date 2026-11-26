import { errorDisplayMessage } from "@t3tools/client-runtime/errors";
import { useAtomRefresh, useAtomValue } from "@effect/atom-react";
import * as Effect from "effect/Effect";
import * as Option from "effect/Option";
import { Atom, AsyncResult } from "effect/reactivity";
import { msg, useGT } from "gt-react-native";
import { useState, type ComponentType } from "react";
import { View } from "react-native";

import { FilePreviewLoading, FilePreviewNotice } from "../features/files/FilePreviewFeedback";
import { pdfInitialPage, pdfLinkUrl, preparePdfPreview } from "../lib/pdfPreview";
import { m } from "../i18n/messages";
import { tryOpenExternalUrl } from "../lib/openExternalUrl";
import { ControlPill } from "./ui/ControlPill";

const preparedPdfAtom = Atom.family((uri: string) =>
  Atom.make(
    // The downloaded copy lives as long as a viewer reads it; Retry refreshes the atom,
    // which closes the scope and discards the copy before downloading again. Acquisition
    // stays interruptible so closing the viewer aborts the download.
    Effect.acquireRelease(
      Effect.tryPromise({
        try: (signal) => {
          const prepared = preparePdfPreview(uri, signal);
          // An interrupt can land after the copy exists but before acquireRelease owns it.
          signal.addEventListener("abort", () => {
            void prepared.then(
              (file) => file?.dispose(),
              () => undefined,
            );
          });
          return prepared;
        },
        catch: (cause) =>
          cause instanceof Error
            ? (errorDisplayMessage(cause, m) ?? cause.message)
            : m(msg("The PDF could not be loaded.")),
      }).pipe(
        Effect.filterOrElse(
          (file) => file !== null,
          () => Effect.interrupt,
        ),
        Effect.interruptible,
      ),
      (file) => Effect.sync(file.dispose),
    ),
  ).pipe(Atom.withLabel(`pdf-preview:${uri}`)),
);

export interface PreparedPdfRendererProps {
  readonly uri: string;
  readonly initialPage: number;
  readonly onLink: (href: string) => void;
  readonly onError: () => void;
}

export function PreparedPdfPreview(props: {
  readonly uri: string;
  readonly Renderer: ComponentType<PreparedPdfRendererProps>;
}) {
  const gt = useGT();
  const atom = preparedPdfAtom(props.uri);
  const prepared = useAtomValue(atom);
  const refresh = useAtomRefresh(atom);
  // A render failure belongs to the downloaded copy that failed; Retry replaces it.
  const [unrenderable, setUnrenderable] = useState<unknown>(null);
  const file = prepared._tag === "Success" && !prepared.waiting ? prepared.value : null;
  const error =
    file !== null && unrenderable === file
      ? gt("The PDF could not be rendered. It may be damaged or password protected.")
      : prepared._tag === "Failure" && !prepared.waiting
        ? Option.getOrElse(AsyncResult.error(prepared), () => gt("The PDF could not be loaded."))
        : null;
  const localUri = file?.uri ?? null;

  if (error) {
    return (
      <View className="flex-1 gap-4 bg-card">
        <FilePreviewNotice title={gt("Could not load PDF")}>{error}</FilePreviewNotice>
        <View className="items-center">
          <ControlPill label={gt("Try again")} variant="pill" onPress={refresh} />
        </View>
      </View>
    );
  }
  if (localUri === null)
    return <FilePreviewLoading message={gt("Loading PDF...")} background="card" />;

  return (
    <props.Renderer
      key={localUri}
      uri={localUri}
      initialPage={pdfInitialPage(props.uri) - 1}
      onLink={(href) => {
        const url = pdfLinkUrl(href, props.uri);
        if (url !== null) void tryOpenExternalUrl(url, "file-preview");
      }}
      onError={() => {
        setUnrenderable(file);
      }}
    />
  );
}
