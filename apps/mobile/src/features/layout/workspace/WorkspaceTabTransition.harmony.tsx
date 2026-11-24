import type { PropsWithChildren } from "react";
import Animated, {
  Easing,
  FadeIn,
  LayoutAnimationConfig,
  ReduceMotion,
} from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { MOBILE_MOTION } from "../../../lib/designTokens";

const TAB_ENTER = FadeIn.duration(MOBILE_MOTION.adjust)
  .easing(Easing.out(Easing.cubic))
  .withInitialValues({ opacity: 0.8 })
  .reduceMotion(ReduceMotion.System);

export function WorkspaceTabTransition({ children, tab }: PropsWithChildren<{ tab: string }>) {
  const { top } = useSafeAreaInsets();
  // These lists have no app bar to account for the status bar.
  const paddingTop = tab === "pullRequests" || tab === "issues" ? top : 0;

  return (
    <LayoutAnimationConfig skipEntering>
      <Animated.View key={tab} entering={TAB_ENTER} className="flex-1" style={{ paddingTop }}>
        {children}
      </Animated.View>
    </LayoutAnimationConfig>
  );
}
