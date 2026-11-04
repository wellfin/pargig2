/**
 * Which theme the admin panel wears.
 *
 * Change this one string, rebuild, upload the new dist. Nothing else
 * in the app needs touching — every colour in App.css reads from a
 * custom property, and a theme file in src/themes/ overrides them.
 *
 *   'studio'    navy sidebar, coloured headline cards
 *   'pargig'    the original: dark brown sidebar, bright orange accent
 *   'slate'     white sidebar, indigo accent, cool neutrals
 *   'midnight'  dark sidebar, light content, orange accent
 *   'clay'      cream ground, terracotta, softer corners
 *   'dusk'      full dark
 *
 * 'pargig' is the :root block in App.css rather than a file of its
 * own, so it needs no data-theme attribute — which also means it is
 * what shows if this value is ever misspelt.
 */
export const THEME = 'studio';
