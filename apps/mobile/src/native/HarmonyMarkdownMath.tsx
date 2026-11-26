import { Suspense, use, useMemo, useState, type ReactNode } from "react";
import { StyleSheet, View, useWindowDimensions } from "react-native";
import { WebView } from "react-native-webview";

import { harmonyMathDocument } from "./harmonyMathDocument";
import type { NativeMarkdownTextStyle } from "./SelectableMarkdownText.types";

const SEND_HEIGHT = `
  if (typeof MathMLElement === "function") {
    window.ReactNativeWebView.postMessage(String(
      Math.ceil(document.querySelector("main").getBoundingClientRect().height)
    ));
  }
  true;
`;

let katexLoad: Promise<typeof import("katex") | null> | undefined;

interface MathProps {
  readonly tex: string;
  readonly textStyle: NativeMarkdownTextStyle;
  readonly fallback: ReactNode;
}

export function HarmonyMarkdownMath(props: MathProps) {
  return (
    <Suspense fallback={props.fallback}>
      <TypesetMath {...props} />
    </Suspense>
  );
}

function TypesetMath(props: MathProps) {
  const katex = use((katexLoad ??= import("katex").catch(() => null)));
  const { fontScale } = useWindowDimensions();
  const { color, fontSize } = props.textStyle;
  const html = useMemo(
    () =>
      katex && harmonyMathDocument(katex.renderToString, props.tex, fontSize * fontScale, color),
    [katex, props.tex, fontScale, fontSize, color],
  );
  if (!html) return props.fallback;
  return <MathDocument key={html} html={html} fallback={props.fallback} />;
}

function MathDocument({ html, fallback }: { readonly html: string; readonly fallback: ReactNode }) {
  const [height, setHeight] = useState(0);
  const [failed, setFailed] = useState(false);
  if (failed) return fallback;
  return (
    <View style={height ? { height } : undefined}>
      {height ? null : fallback}
      <WebView
        source={{ html }}
        style={styles.webView}
        containerStyle={height ? styles.container : styles.loading}
        originWhitelist={["about:blank"]}
        onShouldStartLoadWithRequest={(request) => request.url === "about:blank"}
        injectedJavaScript={SEND_HEIGHT}
        onMessage={({ nativeEvent }) => {
          if (!/^\d{1,4}$/.test(nativeEvent.data)) return;
          const measured = Number(nativeEvent.data);
          if (measured > 0 && measured <= 1_024) setHeight(measured);
          else setFailed(true);
        }}
        onError={() => setFailed(true)}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  webView: { backgroundColor: "transparent" },
  container: { flex: 1 },
  loading: { position: "absolute", top: 0, bottom: 0, left: 0, right: 0, opacity: 0 },
});
