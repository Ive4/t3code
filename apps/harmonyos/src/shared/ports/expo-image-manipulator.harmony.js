import { File } from "./expo-file-system.harmony.js";
import { TurboModuleRegistry } from "react-native";

export const SaveFormat = { JPEG: "jpeg", PNG: "png" };

export const ImageManipulator = {
  manipulate(source) {
    const native = TurboModuleRegistry.getEnforcing("T3ImageManipulator");
    const uri = typeof source === "string" ? source : source.sourceUri;
    let size;
    const context = {
      resize(dimensions) {
        size = dimensions;
        return context;
      },
      async renderAsync() {
        // Keep only the source URI and dimensions until the final decode size is known.
        const { width, height } = size ?? (await native.getSize(uri));
        return {
          sourceUri: uri,
          width,
          height,
          release() {},
          async saveAsync({ format, compress, base64 }) {
            const output = new File(await native.render(uri, width, height, format, compress));
            try {
              return {
                uri: output.uri,
                width,
                height,
                ...(base64 ? { base64: await output.base64() } : {}),
              };
            } catch (error) {
              try {
                if (output.exists) output.delete();
              } catch (cleanupError) {
                console.warn("[composer-images] could not remove failed render", cleanupError);
              }
              throw error;
            }
          },
        };
      },
    };
    return context;
  },
};
