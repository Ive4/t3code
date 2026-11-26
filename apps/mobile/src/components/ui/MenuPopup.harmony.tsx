import { Pressable, View } from "react-native";
import { isAppSymbolName } from "./AppSymbol.android";
import { SymbolView } from "./AppSymbol";
import { AppText as Text } from "./AppText";
import type { MenuPopupProps } from "./MenuPopup";

export function MenuPopup({ actions, title, parent, onPress, onBack }: MenuPopupProps) {
  return (
    <>
      {parent ? (
        <Pressable accessibilityRole="button" className="px-4 py-3" onPress={onBack}>
          <Text className="text-sm text-foreground">‹ {parent.title}</Text>
        </Pressable>
      ) : title ? (
        <Text className="px-4 pb-1 pt-2 text-xs text-foreground-muted">{title}</Text>
      ) : null}
      {actions.map((action, index) => {
        const disabled = action.attributes?.disabled === true;
        const trailingIcon =
          (action.subactions?.length ?? 0) > 0
            ? "chevron.right"
            : action.state === "on"
              ? "checkmark"
              : null;
        return (
          <Pressable
            key={action.id ?? `${index}-${action.title}`}
            accessibilityRole="button"
            accessibilityState={{ disabled, selected: action.state === "on" }}
            disabled={disabled}
            className="min-h-12 flex-row items-center gap-3 px-4 py-2 active:bg-subtle disabled:opacity-50"
            onPress={() => onPress(action)}
          >
            {action.image && isAppSymbolName(action.image) ? (
              <SymbolView
                name={action.image}
                size={18}
                {...(action.imageColor !== undefined
                  ? { tintColor: action.imageColor }
                  : { tintColorClassName: "accent-icon-muted" })}
              />
            ) : null}
            <View className="flex-1">
              <Text
                className={
                  action.attributes?.destructive
                    ? "text-sm text-danger-foreground"
                    : "text-sm text-foreground"
                }
              >
                {action.title}
              </Text>
              {action.subtitle ? (
                <Text className="text-xs text-foreground-muted">{action.subtitle}</Text>
              ) : null}
            </View>
            {trailingIcon ? (
              <SymbolView name={trailingIcon} size={16} tintColorClassName="accent-icon-muted" />
            ) : null}
          </Pressable>
        );
      })}
    </>
  );
}
