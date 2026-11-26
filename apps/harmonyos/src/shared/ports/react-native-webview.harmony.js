import React, {
  useId,
  useImperativeHandle,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { DeviceEventEmitter, requireNativeComponent, View } from "react-native";
import codegenNativeCommands from "react-native/Libraries/Utilities/codegenNativeCommands";
import { allowWebNavigation } from "./webViewNavigation";

const NativeView = requireNativeComponent("T3WebView");
const commands = codegenNativeCommands({ supportedCommands: ["injectJavaScript", "navigate"] });
const defaults = ["http://*", "https://*"];

function WebDocument({ forwardedRef, ...props }) {
  const viewId = useId();
  const view = useRef(null);
  const latest = useRef(props);
  const [ready, setReady] = useState(false);
  const [loading, setLoading] = useState(true);
  useLayoutEffect(() => {
    latest.current = props;
  });
  useImperativeHandle(
    forwardedRef,
    () => ({
      injectJavaScript(script) {
        if (view.current) commands.injectJavaScript(view.current, script);
      },
    }),
    [],
  );
  useLayoutEffect(() => {
    const subscription = DeviceEventEmitter.addListener("T3WebView:" + viewId, (event) => {
      const current = latest.current;
      if (event.type === "request") {
        if (
          view.current &&
          allowWebNavigation(
            event.url,
            true,
            current.originWhitelist ?? defaults,
            current.onShouldStartLoadWithRequest,
          )
        ) {
          commands.navigate(view.current, event.requestId);
        }
        return;
      }
      if (event.type === "onLoadEnd" || event.type === "onError") setLoading(false);
      current[event.type]?.({ nativeEvent: event });
    });
    // oxlint-disable-next-line react/set-state-in-effect -- ArkWeb can emit as soon as its native view mounts.
    setReady(true);
    return () => subscription.remove();
  }, [viewId]);
  return (
    <View style={[{ flex: 1 }, props.containerStyle]}>
      {ready && (
        <NativeView
          ref={view}
          collapsable={false}
          nativeID={viewId}
          options={props.options}
          accessibilityLabel={props.accessibilityLabel}
          style={[{ flex: 1 }, props.style]}
        />
      )}
      {props.startInLoadingState && loading ? props.renderLoading?.() : null}
    </View>
  );
}

export const WebView = React.forwardRef((props, ref) => {
  const { uri, html, baseUrl, harmonyWebFrames } = props.source;
  const mixed = props.mixedContentMode === "always";
  const messaging = Boolean(props.onMessage);
  const windows = Boolean(props.onOpenWindow);
  const {
    injectedJavaScript: script = "",
    javaScriptEnabled: allowScript = true,
    domStorageEnabled: storage = true,
    incognito = false,
    mediaPlaybackRequiresUserAction: mediaGesture = true,
  } = props;
  const options = useMemo(
    () =>
      JSON.stringify({
        source: { uri, html, baseUrl, harmonyWebFrames },
        mixed,
        messaging,
        windows,
        script,
        allowScript,
        storage,
        incognito,
        mediaGesture,
      }),
    [
      uri,
      html,
      baseUrl,
      harmonyWebFrames,
      mixed,
      messaging,
      windows,
      script,
      allowScript,
      storage,
      incognito,
      mediaGesture,
    ],
  );
  return <WebDocument key={options} {...props} options={options} forwardedRef={ref} />;
});
export default WebView;
