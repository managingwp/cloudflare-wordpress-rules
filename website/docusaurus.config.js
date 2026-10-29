// @ts-check
const { themes: prismThemes } = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Cloudflare WordPress Rules',
  tagline:
    'Cloudflare WAF rules, API tokens and Turnstile widgets for WordPress sites',
  favicon: 'img/favicon.svg',

  // GitHub Pages project site: https://managingwp.github.io/cloudflare-wordpress-rules/
  url: 'https://managingwp.github.io',
  baseUrl: '/cloudflare-wordpress-rules/',

  organizationName: 'managingwp',
  projectName: 'cloudflare-wordpress-rules',
  trailingSlash: false,

  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          path: '../docs',
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
          editUrl:
            'https://github.com/managingwp/cloudflare-wordpress-rules/tree/main/docs/',
        },
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'img/social-card.svg',
      navbar: {
        title: 'Cloudflare WordPress Rules',
        logo: {
          alt: 'Cloudflare WordPress Rules',
          src: 'img/logo.svg',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'docs',
            position: 'left',
            label: 'Docs',
          },
          {
            href: 'https://managingwp.github.io/cloudflare-wordpress-rules/generator/',
            label: 'Generator',
            position: 'right',
          },
          {
            href: 'https://github.com/managingwp/cloudflare-wordpress-rules',
            label: 'GitHub',
            position: 'right',
          },
          {
            href: 'https://github.com/managingwp/cloudflare-wordpress-rules/releases',
            label: 'Releases',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              { label: 'Getting started', to: '/getting-started/installation' },
              { label: 'Commands', to: '/commands/waf-rules' },
              { label: 'Profile format', to: '/reference/profile-format' },
            ],
          },
          {
            title: 'Rules',
            items: [
              { label: 'Beta rules', to: '/reference/beta-rules' },
              { label: 'Stable rules', to: '/reference/stable-rules' },
              { label: 'Release notes', to: '/release-notes' },
            ],
          },
          {
            title: 'Project',
            items: [
              {
                label: 'GitHub',
                href: 'https://github.com/managingwp/cloudflare-wordpress-rules',
              },
              {
                label: 'Releases',
                href: 'https://github.com/managingwp/cloudflare-wordpress-rules/releases',
              },
              { label: 'Changelog', to: '/changelog' },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} Managing WP.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ['bash', 'json', 'yaml', 'diff'],
      },
      colorMode: {
        defaultMode: 'light',
        respectPrefersColorScheme: true,
      },
      tableOfContents: {
        minHeadingLevel: 2,
        maxHeadingLevel: 3,
      },
    }),
};

module.exports = config;
