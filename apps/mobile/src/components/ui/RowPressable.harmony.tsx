import { useState, type ComponentProps, type ReactNode } from "react";
import { Pressable, View } from "react-native";

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
      <View
        pointerEvents="none"
        className={cn("absolute inset-0", interactionClassName)}
        style={{ opacity: props.disabled || !hovered ? 0 : interactionOpacity }}
      />
      {children}
    </Pressable>
  );
}
