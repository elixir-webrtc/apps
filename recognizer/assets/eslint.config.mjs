import globals from "globals";
import pluginJs from "@eslint/js";
import prettierPlugin from 'eslint-plugin-prettier';
import prettierConfig from 'eslint-config-prettier';

export default [
  {
    files: ['**/*.js'],
    languageOptions: {
      ecmaVersion: 2021,
      sourceType: "module",
      globals: globals.browser
    },
    plugins: {
      prettier: prettierPlugin
    },
    rules: {
      "prettier/prettier": "error",
      "no-unused-vars": [
        "error",
        {
          "argsIgnorePattern": "^_",
          "varsIgnorePattern": "^_"
        }
      ]
    },
    settings: {
      prettier: prettierConfig
    }
  },
  pluginJs.configs.recommended,
];
