import { useState, type ComponentProps, type ReactNode } from "react";
import { Pressable } from "react-native";
import Animated, { useReducedMotion } from "react-native-reanimated";

import { cn } from "../../lib/cn";

export function RowPressable({
  children,
  className,
  interactionClassName = "bg-row-hover",
  interactionOpacity = 1,
  onHoverIn,
  onHoverOut,
  ...props
}: Omit<ComponentProps<typeof Pressable>, "children"> & {
  readonly children: ReactNode;
  readonly interactionClassName?: string;
  readonly interactionOpacity?: number;
}) {
  const [hovered, setHovered] = useState(false);
  const reduceMotion = useReducedMotion();
  return (
    <Pressable
      {...props}
      className={cn("relative overflow-hidden", className)}
      onHoverIn={(event) => {
        setHovered(true);
        onHoverIn?.(event);
      }}
      onHoverOut={(event) => {
        setHovered(false);
        onHoverOut?.(event);
      }}
    >
      {({ pressed }) => (
        <>
          <Animated.View
            pointerEvents="none"
            className={cn("absolute inset-0", interactionClassName)}
            style={{
              opacity: !props.disabled && (hovered || pressed) ? interactionOpacity : 0,
              transitionProperty: "opacity",
              transitionDuration: reduceMotion ? 0 : pressed ? 80 : 120,
              transitionTimingFunction: "ease-out",
            }}
          />
          {children}
        </>
      )}
    </Pressable>
  );
}
