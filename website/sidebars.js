// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    {
      type: 'category',
      label: 'Getting started',
      collapsed: false,
      items: ['intro', 'getting-started/installation', 'getting-started/authentication', 'getting-started/release-notifications'],
    },
    {
      type: 'category',
      label: 'Guides',
      items: [
        'guides/profile-management',
        'guides/multi-zone',
        'guides/skip-action',
        'guides/block-response',
        'guides/rate-limiting',
        'guides/migrate-to-rulesets',
      ],
    },
    {
      type: 'category',
      label: 'Commands',
      items: ['commands/waf-rules', 'commands/token', 'commands/turnstile'],
    },
    {
      type: 'category',
      label: 'Tools',
      items: ['tools/rule-generator'],
    },
    {
      type: 'category',
      label: 'Reference',
      items: [
        'reference/profile-format',
        'reference/beta-rules',
        'reference/stable-rules',
        'release-notes',
        'changelog',
        'reference/repository-layout',
        {
          type: 'category',
          label: 'Cloudflare Rulesets API',
          items: [
            'reference/cloudflare-rulesets/api-reference',
            'reference/cloudflare-rulesets/add-rules-to-custom-ruleset',
            'reference/cloudflare-rulesets/deploy-custom-ruleset',
            'reference/cloudflare-rulesets/firewall-rules-upgrade',
            'reference/cloudflare-rulesets/ruleset-api-quickstart',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: 'Contributing',
      items: [
        'contributing/development',
        'contributing/docs-site',
        'contributing/roadmap',
      ],
    },
    {
      type: 'category',
      label: 'History',
      items: [
        'reference/history/ruleset-migration-plan',
        'reference/history/legacy-v2-rules',
      ],
    },
  ],
};

module.exports = sidebars;
