import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";

export default [
  {
    ignores: [
      "**/node_modules/",
      "**/dist/",
      "**/bin/",
      "**/certs/",
      "**/docs/",
      "**/.vscode/",
    ],
  },

  js.configs.recommended,

  ...tseslint.configs.recommended,

  {
    files: ["**/*.{js,mjs,cjs,ts,jsx,tsx}"],

    languageOptions: {
      globals: {
        ...globals.node,
      },

      ecmaVersion: "latest",
      sourceType: "module",
    },

    rules: {
      // TypeScript
      "@typescript-eslint/explicit-function-return-type": "off",
      "@typescript-eslint/no-explicit-any": "off",
      "@typescript-eslint/no-var-requires": "off",
      "@typescript-eslint/no-namespace": "off",
      "@typescript-eslint/no-duplicate-enum-values": "off",

      "@typescript-eslint/no-unused-expressions": [
        "error",
        {
          allowShortCircuit: true,
          allowTernary: true,
          allowTaggedTemplates: true,
        },
      ],

      // JavaScript
      curly: ["error", "multi-line"],
      eqeqeq: ["error", "always"],
      "no-var": "off",
      "prefer-const": "error",
      "arrow-body-style": ["error", "as-needed"],
      "prefer-template": "error",
      "no-useless-constructor": "off",

      "no-empty-function": [
        "error",
        {
          allow: ["constructors"],
        },
      ],

      "no-prototype-builtins": "off",
    },
  },
];
