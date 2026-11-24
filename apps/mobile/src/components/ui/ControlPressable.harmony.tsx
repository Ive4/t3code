import { useState } from "react";
import { Pressable, StyleSheet, type PressableProps } from "react-native";
import Animated, { useReducedMotion } from "react-native-reanimated";

import { MOBILE_MOTION } from "../../lib/designTokens";

const AnimatedPressable = Animated.createAnimatedComponent(Pressable);

export function ControlPressable({ onPressIn, onPressOut, style, ...props }: PressableProps) {
  const [pressed, setPressed] = useState(false);
  const reduceMotion = useReducedMotion();
  const resolvedStyle = typeof style === "function" ? style({ pressed }) : style;
  const opacity = StyleSheet.flatten(resolvedStyle)?.opacity ?? 1;
  return (
    <AnimatedPressable
      {...props}
      onPressIn={(event) => {
        setPressed(true);
        onPressIn?.(event);
      }}
      onPressOut={(event) => {
        setPressed(false);
        onPressOut?.(event);
      }}
      style={[
        resolvedStyle,
        {
          opacity: pressed && !props.disabled ? opacity * 0.7 : opacity,
          transitionProperty: "opacity",
          transitionDuration: reduceMotion ? 0 : MOBILE_MOTION.adjust,
          transitionTimingFunction: "ease-out",
        },
      ]}
    />
  );
}
