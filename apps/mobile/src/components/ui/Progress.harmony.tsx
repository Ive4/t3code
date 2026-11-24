import { I18nManager, View } from "react-native";
import Animated, { useReducedMotion, type CSSAnimationKeyframes } from "react-native-reanimated";

import { MOBILE_MOTION } from "../../lib/designTokens";
import { clampProgress, type ProgressProps } from "./Progress.types";

const movement = I18nManager.isRTL ? -1 : 1;
const indeterminate: CSSAnimationKeyframes = {
  from: { transform: [{ translateX: `${-100 * movement}%` }] },
  to: { transform: [{ translateX: `${300 * movement}%` }] },
};

export function Progress(props: ProgressProps) {
  const value = clampProgress(props.value);
  const reduceMotion = useReducedMotion();
  return (
    <View
      className={props.className}
      accessible
      accessibilityRole="progressbar"
      accessibilityLabel={props.label}
      accessibilityValue={
        value === undefined ? undefined : { min: 0, max: 100, now: Math.round(value * 100) }
      }
      accessibilityState={{ busy: value === undefined }}
    >
      <View className="h-1 overflow-hidden rounded-full bg-subtle">
        {value === undefined ? (
          <Animated.View
            className="h-full w-1/3 rounded-full bg-primary"
            style={{
              animationName: reduceMotion ? undefined : indeterminate,
              animationDuration: 1000,
              animationIterationCount: "infinite",
              animationTimingFunction: "ease-in-out",
            }}
          />
        ) : (
          <Animated.View
            className="h-full rounded-full bg-primary"
            style={{
              transformOrigin: I18nManager.isRTL ? "right center" : "left center",
              transform: [{ scaleX: value }],
              transitionProperty: "transform",
              transitionDuration: reduceMotion ? 0 : MOBILE_MOTION.adjust,
              transitionTimingFunction: "ease-out",
            }}
          />
        )}
      </View>
    </View>
  );
}
