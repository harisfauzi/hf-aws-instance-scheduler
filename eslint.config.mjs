import pluginJs from "@eslint/js";
import eslintPluginYml from "eslint-plugin-yml";
import json from "eslint-plugin-json";
import eslintPluginPrettierRecommended from "eslint-plugin-prettier/recommended";

export default [
  {files: ["**/*.js"], languageOptions: {sourceType: "script"}},
  pluginJs.configs.recommended,
  ...eslintPluginYml.configs["flat/standard","flat/prettier"],
  {
    rules: {
      "yml/no-empty-mapping-value": "off"
    }
  },
  {
    files: ["**/*.json"],
    ...json.configs["recommended"]
  },
  eslintPluginPrettierRecommended,
];