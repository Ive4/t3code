import * as NodeFS from "node:fs";
import * as NodeModule from "node:module";
import * as NodeURL from "node:url";
import { transformFromAstSync } from "@babel/core";
import { expect, it } from "vitest";

import harmonyTransformer from "./shared-harmony-transformer.cjs";

it("lets Harmony keyboard move and end frames update the sticky keyboard offset", () => {
  const mobileRequire = NodeModule.createRequire(
    new URL("../../mobile/package.json", import.meta.url),
  );
  const filename = mobileRequire.resolve("react-native-keyboard-controller/src/animated.tsx");
  const src = NodeFS.readFileSync(filename, "utf8");
  const { ast } = harmonyTransformer.transform({
    filename,
    src,
    options: {
      dev: false,
      enableBabelRCLookup: false,
      hermesParser: false,
      platform: "harmony",
      projectRoot: NodeURL.fileURLToPath(new URL("..", import.meta.url)),
    },
  });
  const code = transformFromAstSync(ast, src, { babelrc: false, configFile: false })?.code ?? "";

  const platform = code.split("\n").find((line) => /\b(?:const|var) OS = /.test(line));
  expect(platform).toMatch(/\bPlatform\.OS === "harmony" \? "android" : .*\bPlatform\.OS/);
  expect(code).toContain('onKeyboardMoveStart: OS === "ios" ? onKeyboardMove : undefined');
  expect(code.match(/updateSharedValues\(event, \["android"\]\)/g) ?? []).toHaveLength(2);
  expect(code).toContain('onKeyboardMove: OS === "android" ? onKeyboardMove : undefined');
  expect(code).toContain('onKeyboardMoveEnd: OS === "android" ? onKeyboardMove : undefined');
});
