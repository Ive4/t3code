module.exports = {
  presets: ["module:@react-native/babel-preset"],
  plugins: [
    "@babel/plugin-transform-export-namespace-from",
    function transformImportMeta({ types }) {
      return {
        visitor: {
          MetaProperty(path) {
            // Hermes cannot parse import.meta; bundled modules have no per-module environment.
            if (path.node.meta.name === "import" && path.node.property.name === "meta") {
              path.replaceWith(types.objectExpression([]));
            }
          },
        },
      };
    },
  ],
};
