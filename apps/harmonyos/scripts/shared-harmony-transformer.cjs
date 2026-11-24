const { createRequire } = require("node:module");
const path = require("node:path");

const metroRequire = createRequire(require.resolve("@react-native/metro-config"));
const transformer = metroRequire("@react-native/metro-babel-transformer");
const mobileRequire = createRequire(path.resolve(__dirname, "../../mobile/package.json"));
const worklets = mobileRequire("react-native-worklets/plugin");

module.exports = {
  ...transformer,
  transform(args) {
    const filename = args.filename.replaceAll("\\", "/");
    let source = args.src;
    if (
      filename.includes("/react-native-screens/") &&
      (filename.endsWith("/src/core.ts") || filename.endsWith("/lib/module/core.js"))
    ) {
      source = source.replace(
        "Platform.OS === 'windows'",
        "Platform.OS === 'windows' || Platform.OS === 'harmony'",
      );
    }
    if (
      filename.includes("/react-native-keyboard-controller/") &&
      /\/specs\/KeyboardControllerViewNativeComponent\.(?:ts|js)$/.test(filename)
    ) {
      const componentName = /(['"])KeyboardControllerView\1/;
      if (!componentName.test(source)) {
        throw new Error("The keyboard controller's native component name changed: " + filename);
      }
      source = source.replace(componentName, '"RNKeyboardControllerView"');
    }
    if (
      filename.includes("/react-native-gesture-handler/") &&
      filename.endsWith("/src/v3/detectors/common.ts")
    ) {
      source = source.replace("display: 'contents'", "display: 'flex'");
    }
    if (
      filename.includes("/react-native-gesture-handler/") &&
      (filename.endsWith("/src/v3/detectors/NativeDetector.tsx") ||
        filename.endsWith("/src/v3/detectors/VirtualDetector/InterceptingGestureDetector.tsx"))
    ) {
      source = source.replace(
        "<NativeDetectorComponent",
        "<NativeDetectorComponent collapsable={false}",
      );
    }
    if (
      filename.includes("/react-native-gesture-handler/") &&
      filename.endsWith("/src/v3/detectors/NativeDetector.tsx")
    ) {
      // A materialized detector must take the flex space its child would occupy directly.
      source = source
        .replace("import { Platform }", "import { Platform, StyleSheet }")
        .replace(
          "  const { handleStartShouldSetResponder }",
          "  const childFlex = React.isValidElement(children) ? StyleSheet.flatten(children.props.style)?.flex : undefined;\n" +
            "  const { handleStartShouldSetResponder }",
        )
        .replace(
          "style={nativeDetectorStyles.detector}",
          "style={[nativeDetectorStyles.detector, childFlex === undefined ? undefined : { flex: childFlex }]}",
        );
    }
    if (
      filename.includes("/node_modules/expo/") &&
      /\/(?:src|build)\/winter\/runtime\.native\.(?:ts|js)$/.test(filename)
    ) {
      // Expo's fetch needs a native module the Harmony host does not provide.
      const selection = /(\b(?:const|var)\s+useRnFetch)\s*=\s*[^;]+;/;
      if (!selection.test(source))
        throw new Error("Expo's React Native fetch selection changed: " + filename);
      source = source.replace(selection, "$1 = true;");
    }
    return transformer.transform({
      ...args,
      src: source,
      plugins: [...(args.plugins ?? []), worklets],
    });
  },
};
