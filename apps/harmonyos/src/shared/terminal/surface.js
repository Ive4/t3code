import React, {
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from "react";
import { setStringAsync } from "expo-clipboard";
import { useGT } from "gt-react-native";
import { WebView } from "react-native-webview";
import html from "./document";

const source = { html };

function TerminalWebSurface({ ref, onSurfaceUnavailable, ...props }) {
  const gt = useGT();
  const copyLabel = gt("Copy", { $context: "verb" });
  const selectAllLabel = gt("Select all");
  const web = useRef(null);
  const pending = useRef(null);
  const sequence = useRef(0);
  const deadline = useRef(null);
  const [ready, setReady] = useState(false);
  const config = useMemo(
    () => ({
      backgroundColor: props.backgroundColor,
      foregroundColor: props.foregroundColor,
      cursor: /^cursor-color = (.+)$/m.exec(props.themeConfig)?.[1] ?? props.foregroundColor,
      palette: [...props.themeConfig.matchAll(/^palette = \d+=(.+)$/gm)].map((match) => match[1]),
      fontSize: props.fontSize,
      sharedGrid: props.sharedGrid,
      readOnly: props.readOnly,
      appearanceScheme: props.appearanceScheme,
      copyLabel,
      selectAllLabel,
    }),
    [
      props.backgroundColor,
      props.foregroundColor,
      props.themeConfig,
      props.fontSize,
      props.sharedGrid,
      props.readOnly,
      props.appearanceScheme,
      copyLabel,
      selectAllLabel,
    ],
  );

  const command = useCallback((value) => {
    web.current?.injectJavaScript(
      `window.terminalCommand ? window.terminalCommand(${JSON.stringify(value)}) : window.ReactNativeWebView.postMessage('{"type":"failed"}');true;`,
    );
  }, []);
  const failed = useCallback(() => {
    clearTimeout(deadline.current);
    onSurfaceUnavailable?.();
    pending.current?.reject(new Error("Terminal document unavailable"));
    pending.current = null;
  }, [onSurfaceUnavailable]);

  useImperativeHandle(
    ref,
    () => ({
      resetInput: async () => command({ type: "resetInput" }),
      writeOutput(data, reset) {
        const id = ++sequence.current;
        return new Promise((resolve, reject) => {
          pending.current = { id, resolve, reject };
          deadline.current = setTimeout(failed, 15000);
          command({ type: "write", data, reset, id });
        });
      },
    }),
    [command, failed],
  );
  useEffect(() => {
    deadline.current = setTimeout(failed, 15000);
    return () => {
      clearTimeout(deadline.current);
      pending.current?.reject(new Error("Terminal detached"));
      pending.current = null;
    };
  }, [failed]);
  useEffect(() => {
    if (ready) command({ type: "configure", config });
  }, [config, ready, command]);
  useEffect(() => {
    if (ready && !props.readOnly && (props.autoFocus || props.focusRequest))
      command({ type: "focus" });
  }, [ready, props.autoFocus, props.focusRequest, props.readOnly, command]);
  useEffect(() => {
    if (ready && props.captureRequest) command({ type: "capture" });
  }, [ready, props.captureRequest, command]);

  return (
    <WebView
      ref={web}
      source={source}
      style={props.style}
      originWhitelist={[]}
      onShouldStartLoadWithRequest={() => false}
      domStorageEnabled={false}
      onLoadEnd={() => command({ type: "configure", config })}
      onError={failed}
      onRenderProcessGone={failed}
      onMessage={({ nativeEvent }) => {
        const event = JSON.parse(nativeEvent.data);
        switch (event.type) {
          case "failed":
            failed();
            break;
          case "ready":
            clearTimeout(deadline.current);
            setReady(true);
            break;
          case "resize":
            props.onResize?.({ nativeEvent: { cols: event.cols, rows: event.rows } });
            break;
          case "input":
            if (!props.readOnly) props.onInput?.({ nativeEvent: { data: event.data } });
            break;
          case "paste":
            if (!props.readOnly) props.onPaste?.({ nativeEvent: { text: event.data } });
            break;
          case "copy":
            if (typeof event.data === "string" && event.data) {
              void setStringAsync(event.data).catch((error) => {
                console.error("Terminal clipboard write failed", error);
              });
            }
            break;
          case "capture":
            props.onCapture?.({ nativeEvent: { text: event.data } });
            break;
          case "written":
            if (pending.current?.id === event.id) {
              clearTimeout(deadline.current);
              pending.current.resolve();
              pending.current = null;
            }
        }
      }}
    />
  );
}

export const resolveNativeTerminalSurfaceView = () => TerminalWebSurface;
export const hasNativeTerminalSurface = () => true;
export const supportsNativeTerminalOutput = () => true;
