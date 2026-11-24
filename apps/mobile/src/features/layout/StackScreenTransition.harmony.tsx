import { useIsFocused } from "@react-navigation/native";
import { useLayoutEffect, type PropsWithChildren } from "react";
import Animated, {
  Easing,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withTiming,
} from "react-native-reanimated";

export function StackScreenTransition({ children }: PropsWithChildren) {
  const focused = useIsFocused();
  const reduceMotion = useReducedMotion();
  const progress = useSharedValue(focused && !reduceMotion ? 0 : 1);

  // oxlint-disable-next-line t3code/no-unreasoned-state-sync -- drives native animation on navigation focus changes
  useLayoutEffect(() => {
    if (focused && !reduceMotion) {
      progress.set(0);
      progress.set(withTiming(1, { duration: 180, easing: Easing.out(Easing.cubic) }));
    } else {
      progress.set(1);
    }
  }, [focused, progress, reduceMotion]);

  const style = useAnimatedStyle(() => {
    const remaining = 1 - progress.get();
    return {
      opacity: 1 - remaining * 0.2,
      transform: [{ translateY: remaining * 6 }],
    };
  });

  return (
    <Animated.View className="flex-1" style={style}>
      {children}
    </Animated.View>
  );
}
