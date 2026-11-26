import { useGT } from "gt-react-native";
import { useMemo, useState } from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";

import { useAppearancePreferences } from "../features/settings/appearance/AppearancePreferencesProvider";
import { copyTextWithHaptic } from "../lib/copyTextWithHaptic";
import { CodeBlockFrame, CodeBlockHeaderButton } from "./CodeBlockFrame";
import { HarmonyMarkdownMath } from "./HarmonyMarkdownMath";
import { highlightHarmonyCode } from "./harmonyCodeBlock";
import { MermaidCodeBlock } from "./MermaidCodeBlock";
import type { NativeMarkdownTextStyle } from "./SelectableMarkdownText.types";

type Props = {
  readonly code: string;
  readonly language: string;
  readonly complete: boolean;
  readonly renderMath: boolean;
  readonly textStyle: NativeMarkdownTextStyle;
};

export function HarmonyMarkdownCodeBlock(props: Props) {
  if (props.complete && props.language === "mermaid" && props.code.length <= 12_000) {
    return <MermaidCodeBlock code={props.code} textStyle={props.textStyle} />;
  }
  return <SourceCodeBlock {...props} />;
}

function SourceCodeBlock({ code, complete, language, renderMath, textStyle }: Props) {
  const gt = useGT();
  const { themeAppearance } = useAppearancePreferences();
  const [wrap, setWrap] = useState(false);
  const tokens = useMemo(
    () => (complete ? highlightHarmonyCode(code, language, themeAppearance) : null),
    [code, complete, language, themeAppearance],
  );
  const content = (
    <Text
      selectable
      style={[styles.text, { color: textStyle.codeColor, fontSize: textStyle.fontSize * 0.9 }]}
    >
      {tokens?.map((token) =>
        token.color ? (
          <Text key={token.start} style={{ color: token.color }}>
            {token.content}
          </Text>
        ) : (
          token.content
        ),
      ) ?? code}
    </Text>
  );
  const source = wrap ? (
    <View>{content}</View>
  ) : (
    <ScrollView horizontal keyboardShouldPersistTaps="always">
      {content}
    </ScrollView>
  );
  return (
    <CodeBlockFrame
      label={language}
      textStyle={textStyle}
      actions={
        <>
          <CodeBlockHeaderButton
            icon="text.alignleft"
            label={wrap ? gt("Disable line wrap") : gt("Wrap lines")}
            textStyle={textStyle}
            active={wrap}
            onPress={() => setWrap((value) => !value)}
          />
          <CodeBlockHeaderButton
            icon="doc.on.doc"
            label={gt("Copy code")}
            textStyle={textStyle}
            onPress={() => copyTextWithHaptic(code)}
          />
        </>
      }
    >
      {renderMath ? (
        <HarmonyMarkdownMath tex={code} textStyle={textStyle} fallback={source} />
      ) : (
        source
      )}
    </CodeBlockFrame>
  );
}

const styles = StyleSheet.create({
  text: { fontFamily: "monospace", padding: 12 },
});
