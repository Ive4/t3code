import {
  useEffectEvent,
  useId,
  useImperativeHandle,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import {
  DeviceEventEmitter,
  TextInput,
  TurboModuleRegistry,
  View,
  type TextInputInstance,
  type TurboModule,
} from "react-native";

import { useScaledTextRole } from "../features/settings/appearance/useScaledTextRole";
import {
  DEFAULT_COMPOSER_ENTER_BEHAVIOR,
  type ComposerEnterBehavior,
} from "../lib/composerEnterBehavior";
import { FONT_FAMILIES } from "../lib/fontFamilies";
import type { ComposerEditorProps } from "./T3ComposerEditor.types";

interface ComposerInteraction extends TurboModule {
  setComposerKeyboard(id: string, mode: ComposerEnterBehavior | ""): Promise<void>;
}

export function ComposerEditor({
  ref,
  value,
  selection,
  onSelectionChange,
  onChangeText,
  onContentSizeChange,
  onSubmit,
  onFocus,
  onBlur,
  enterBehavior = DEFAULT_COMPOSER_ENTER_BEHAVIOR,
  style,
  textStyle,
  contentInsetVertical = 0,
  singleLineCentered = false,
  readOnly = false,
  editable = true,
  autoFocus,
  autoCorrect,
  spellCheck,
  scrollEnabled,
  multiline = true,
  placeholder,
}: ComposerEditorProps) {
  const id = useId();
  const inputRef = useRef<TextInputInstance>(null);
  const [focused, setFocused] = useState(false);
  const bodyText = useScaledTextRole("body");
  const canEdit = editable && !readOnly;
  const keyboardMode = focused && canEdit && onSubmit ? enterBehavior : "";

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- enables hardware Return handling only while the editable composer owns focus
  useLayoutEffect(() => {
    if (!keyboardMode) return;
    const keyboard = TurboModuleRegistry.getEnforcing<ComposerInteraction>("T3Interaction");
    void keyboard.setComposerKeyboard(id, keyboardMode).catch(() => {});
    return () => {
      void keyboard.setComposerKeyboard(id, "").catch(() => {});
    };
  }, [id, keyboardMode]);

  const submitFromKeyboard = useEffectEvent((alternate: boolean) => {
    if (focused && canEdit) onSubmit?.(alternate);
  });

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- routes native hardware submit events to the current draft
  useLayoutEffect(() => {
    if (!canEdit) return;
    const submit = DeviceEventEmitter.addListener("T3ComposerSubmit:" + id, (alternate: boolean) =>
      submitFromKeyboard(alternate),
    );
    return () => submit.remove();
  }, [canEdit, id]);

  useImperativeHandle(
    ref,
    () => ({
      focus: () => inputRef.current?.focus(),
      blur: () => inputRef.current?.blur(),
      setSelection: ({ start, end }) => inputRef.current?.setSelection(start, end),
      flushPendingInput: () => Promise.resolve(),
    }),
    [],
  );

  return (
    <View style={[{ minHeight: 0, flexDirection: "row", alignItems: "center" }, style]}>
      <TextInput
        ref={inputRef}
        value={value}
        editable={canEdit}
        selection={selection}
        onSelectionChange={({ nativeEvent }) => onSelectionChange?.(nativeEvent.selection)}
        onContentSizeChange={(event) => onContentSizeChange?.(event.nativeEvent.contentSize)}
        multiline={multiline}
        submitBehavior="newline"
        placeholder={placeholder}
        placeholderTextColorClassName="accent-placeholder"
        autoFocus={autoFocus}
        autoCorrect={autoCorrect}
        spellCheck={spellCheck}
        scrollEnabled={scrollEnabled}
        onChangeText={onChangeText}
        onFocus={() => {
          setFocused(true);
          onFocus?.();
        }}
        onBlur={() => {
          setFocused(false);
          onBlur?.();
        }}
        className="text-foreground"
        style={[
          {
            flex: 1,
            minHeight: 0,
            textAlignVertical: singleLineCentered ? "center" : "top",
            fontFamily: FONT_FAMILIES.regular,
            ...bodyText,
            paddingVertical: contentInsetVertical,
          },
          textStyle,
        ]}
      />
    </View>
  );
}

export type {
  ComposerEditorHandle,
  ComposerEditorProps,
  ComposerEditorSelection,
  ComposerTextPaste,
} from "./T3ComposerEditor.types";
