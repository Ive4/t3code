import { Image as NativeImage } from "react-native";

const resizeModes = {
  cover: "cover",
  contain: "contain",
  fill: "stretch",
  none: "center",
  "scale-down": "contain",
};

export function Image({
  source,
  contentFit = "cover",
  contentPosition: _contentPosition,
  cachePolicy: _cachePolicy,
  transition: _transition,
  recyclingKey,
  tintColor,
  onLoad,
  onError,
  style,
  ...props
}) {
  return (
    <NativeImage
      {...props}
      key={recyclingKey}
      source={typeof source === "string" ? { uri: source } : source}
      resizeMode={resizeModes[contentFit]}
      style={tintColor === undefined ? style : [style, { tintColor }]}
      onLoad={onLoad ? (event) => onLoad({ source: event.nativeEvent.source }) : undefined}
      onError={onError ? (event) => onError({ error: event.nativeEvent.error }) : undefined}
    />
  );
}
