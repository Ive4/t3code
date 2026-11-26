import { useGT } from "gt-react-native";
import { useEffect, useEffectEvent, useId, useLayoutEffect, useRef, useState } from "react";
import { DeviceEventEmitter, requireNativeComponent, View, type ViewProps } from "react-native";

import { FilePreviewLoading, FilePreviewNotice } from "../features/files/FilePreviewFeedback";
import { openAttachmentInViewer } from "../lib/attachmentDownload";
import { isInlinePdfAvailable } from "../lib/nativeFileActions.harmony";
import { PreparedPdfPreview, type PreparedPdfRendererProps } from "./PreparedPdfPreview";
import { ControlPill } from "./ui/ControlPill";

const NativePdf = requireNativeComponent<
  ViewProps & { readonly uri: string; readonly initialPage: number }
>("T3PdfPreview");

type PdfEvent =
  | { readonly type: "ready" | "error" | "unavailable" }
  | { readonly type: "link"; readonly href: string };

function HarmonyPdfRenderer(props: PreparedPdfRendererProps) {
  const gt = useGT();
  const id = useId();
  const [status, setStatus] = useState<"loading" | "ready" | "unavailable">("loading");
  const handleEvent = useEffectEvent((event: PdfEvent) => {
    if (event.type === "link") props.onLink(event.href);
    else if (event.type === "error") props.onError();
    else setStatus(event.type);
  });
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- each native PDF view has its own event stream
  useLayoutEffect(() => {
    const subscription = DeviceEventEmitter.addListener("T3PdfPreview:" + id, (event: PdfEvent) =>
      handleEvent(event),
    );
    return () => subscription.remove();
  }, [id]);
  if (status === "unavailable") return <SystemPdfPreview uri={props.uri} />;
  return (
    <View className="flex-1 bg-card">
      <NativePdf
        nativeID={id}
        uri={props.uri}
        initialPage={props.initialPage}
        collapsable={false}
        style={{ flex: 1, width: "100%" }}
      />
      {status === "loading" ? (
        <View className="absolute inset-0">
          <FilePreviewLoading message={gt("Loading PDF...")} background="card" />
        </View>
      ) : null}
    </View>
  );
}

function SystemPdfPreview(props: { readonly uri: string }) {
  const gt = useGT();
  const pending = useRef<AbortController | null>(null);
  const [status, setStatus] = useState<"idle" | "opening" | "error">("idle");
  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- cancels pending system viewer handoffs when this preview closes
  useEffect(() => () => pending.current?.abort(), []);

  const open = () => {
    if (pending.current) return;
    const controller = new AbortController();
    pending.current = controller;
    setStatus("opening");
    void openAttachmentInViewer({
      uri: props.uri.split("#", 1)[0]!,
      attachment: { name: "preview.pdf", mimeType: "application/pdf" },
      signal: controller.signal,
    })
      .then(
        () => {
          if (!controller.signal.aborted) setStatus("idle");
        },
        () => {
          if (!controller.signal.aborted) setStatus("error");
        },
      )
      .finally(() => {
        pending.current = null;
      });
  };
  return (
    <View className="flex-1 gap-4 bg-card">
      {status === "error" ? (
        <FilePreviewNotice title={gt("Could not open document")}>
          {gt("A compatible viewer must be installed. Check your connection and try again.")}
        </FilePreviewNotice>
      ) : null}
      <View className="flex-1 items-center justify-center">
        <ControlPill
          label={gt("Open PDF")}
          variant="pill"
          disabled={status === "opening"}
          onPress={open}
        />
      </View>
    </View>
  );
}

export function PdfPreview(props: { readonly uri: string }) {
  return isInlinePdfAvailable() ? (
    <PreparedPdfPreview uri={props.uri} Renderer={HarmonyPdfRenderer} />
  ) : (
    <SystemPdfPreview key={props.uri} uri={props.uri} />
  );
}
