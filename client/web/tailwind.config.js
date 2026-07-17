module.exports = {
  content: ['./src/**/*.{html,ts}', './node_modules/flowbite/**/*.js'],
  theme: {
    extend: {
      colors: {
        // Primary colors
        primary: {
          100: '#e0f2fe',
          300: '#7dd3fc',
        },
        // Secondary colors
        secondary: {
          300: '#d1d5db',
          400: '#9ca3af',
          600: '#4b5563',
          700: '#374151',
          800: '#1f2937',
          900: '#111827',
        },
        // Danger color
        danger: '#d93333',

        // Custom colors
        brand: '#3c54f0', // Primary brand color
        brandDark: '#6366f1', // Dark mode brand color

        surface: '#f0f4ff', // Secondary background surface
        surfaceDark: '#1f2937', // Dark mode surface

        content: '#333333', // Main text/content color
        contentMuted: '#9ca3af', // Muted text for dark mode

        baseDark: '#111827', // Dark mode base background

        // Background colors
        pageBackground: '#F9FAFB', // Light page background
        contentArea: '#f7f7fc', // Main content area background
        stepCard: '#e8edf2', // Welcome step/feature card background
        messageBackground: '#F0F2F5', // Message bubble background (light)
        inputBackground: '#E5E7EB', // Input/form backgrounds

        // Border colors
        borderLight: '#EAECF0', // Light borders
        borderButton: '#e3e5e8', // Button borders (light)
        borderDark: '#374151', // Dark borders

        // Text colors
        textMuted: '#6B7280', // Muted text color
        textVeryMuted: '#9CA3AF', // Very muted text
      },
      fontFamily: {
        sans: ['expo-arabic-book', 'sans-serif'],
        expoArabic: ['expo-arabic-book', 'sans-serif'],
        expoArabicBold: ['expo-arabic-bold', 'sans-serif'],
        expoArabicMedium: ['expo-arabic-medium', 'sans-serif'],
        expoArabicLight: ['expo-arabic-light', 'sans-serif'],
      },
      spacing: {
        18: '4.5rem',
      },
      borderRadius: {
        xl: '1rem',
      },
      boxShadow: {
        soft: '0 4px 24px -2px rgb(0 0 0 / 0.1)',
      },
    },
  },
  plugins: [require('flowbite/plugin')],
  darkMode: 'class',
};
