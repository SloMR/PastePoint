import angular from '@angular-eslint/eslint-plugin';
import tslint from '@typescript-eslint/eslint-plugin';
import parser from '@typescript-eslint/parser';
import eslint from '@eslint/js';
import globals from 'globals';
import templateParser from '@angular-eslint/template-parser';
import angularEslint from 'angular-eslint';

const angularRecommended = angularEslint.configs.tsRecommended.find(
  (config) => config.name === 'angular-eslint/ts-recommended'
).rules;

export default [
  // TypeScript configuration
  {
    files: ['**/*.ts'],
    plugins: {
      '@angular-eslint': angular,
      '@typescript-eslint': tslint,
    },
    languageOptions: {
      parser: parser,
      parserOptions: {
        project: './tsconfig.json',
        sourceType: 'module',
      },
      globals: {
        ...globals.jest,
        ...globals.browser,
        ...globals.node,
      },
    },
    rules: {
      ...eslint.configs.recommended.rules,
      ...angularRecommended,
      ...tslint.configs.recommended.rules,
      '@angular-eslint/directive-selector': [
        'error',
        { type: 'attribute', prefix: 'app', style: 'camelCase' },
      ],
      '@angular-eslint/component-selector': [
        'error',
        { type: 'element', prefix: 'app', style: 'kebab-case' },
      ],
      '@typescript-eslint/no-explicit-any': 'off',
      '@angular-eslint/prefer-standalone': 'off',
      // Warn until the zoneless migration converts the remaining Eager components.
      '@angular-eslint/prefer-on-push-component-change-detection': 'warn',
      '@typescript-eslint/no-unused-vars': [
        'warn',
        {
          vars: 'all', // Check all variables
          args: 'after-used', // Check function arguments after the last used one
          ignoreRestSiblings: true, // Ignore rest siblings in destructuring
          argsIgnorePattern: '^_', // Ignore args starting with underscore
          varsIgnorePattern: '^_', // Ignore vars starting with underscore
        },
      ],
    },
  },
  // HTML template configuration
  {
    files: ['**/*.html'],
    plugins: {
      '@angular-eslint': angular,
    },
    languageOptions: {
      parser: templateParser,
    },
    rules: {
      ...angularRecommended,
    },
  },
  {
    files: ['**/*.spec.ts'],
    languageOptions: {
      globals: {
        jasmine: 'writable',
        describe: 'readonly',
        it: 'readonly',
        beforeEach: 'readonly',
        expect: 'readonly',
      },
    },
  },
];
