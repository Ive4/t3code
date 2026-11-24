import { useLayoutEffect, useRef, type PropsWithChildren } from "react";
import Animated, {
  Easing,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withTiming,
} from "react-native-reanimated";

import { MOBILE_MOTION } from "../../../lib/designTokens";

export function WorkspaceTabTransition({ children, tab }: PropsWithChildren<{ tab: string }>) {
  const previousTab = useRef(tab);
  const reduceMotion = useReducedMotion();
  const opacity = useSharedValue(1);

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- animates the native view when the selected tab changes
  useLayoutEffect(() => {
    if (previousTab.current === tab) return;
    previousTab.current = tab;
    if (reduceMotion) return;
    opacity.set(0.85);
    opacity.set(
      withTiming(1, { duration: MOBILE_MOTION.adjust, easing: Easing.out(Easing.cubic) }),
    );
  }, [opacity, reduceMotion, tab]);

  const style = useAnimatedStyle(() => ({ opacity: opacity.get() }));
  return (
    <Animated.View className="flex-1" style={style}>
      {children}
    </Animated.View>
  );
}
