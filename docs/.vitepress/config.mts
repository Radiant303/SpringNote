import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'SpringNote',
  description: 'AI-native note taking for daily work, memory, and review.',
  base: process.env.DOCS_BASE || '/',
  cleanUrls: true,
  lastUpdated: true,
  head: [
    ['link', { rel: 'icon', href: `${process.env.DOCS_BASE || '/'}images/logo.png` }],
    ['meta', { name: 'theme-color', content: '#16b981' }]
  ],
  locales: {
    root: {
      label: '简体中文',
      lang: 'zh-CN',
      title: 'SpringNote',
      description: '面向工作记录、AI 整理和长期回顾的智能便签。',
      themeConfig: {
        nav: [
          { text: '首页', link: '/' },
          { text: '功能', link: '/features' },
          { text: '模型配置', link: '/models' },
          { text: '桌面体验', link: '/desktop' },
          { text: 'GitHub', link: 'https://github.com/Radiant303/SpringNote' }
        ],
        sidebar: [
          {
            text: '产品文档',
            items: [
              { text: '功能概览', link: '/features' },
              { text: '模型配置', link: '/models' },
              { text: '桌面体验', link: '/desktop' }
            ]
          }
        ],
        outline: { label: '本页目录' },
        docFooter: {
          prev: '上一页',
          next: '下一页'
        },
        lastUpdated: {
          text: '最后更新',
          formatOptions: {
            dateStyle: 'medium',
            timeStyle: 'short'
          }
        }
      }
    },
    en: {
      label: 'English',
      lang: 'en-US',
      title: 'SpringNote',
      description: 'AI-native notes for work logs, structured memory, and review.',
      themeConfig: {
        nav: [
          { text: 'Home', link: '/en/' },
          { text: 'Features', link: '/en/features' },
          { text: 'Models', link: '/en/models' },
          { text: 'Desktop', link: '/en/desktop' },
          { text: 'GitHub', link: 'https://github.com/Radiant303/SpringNote' }
        ],
        sidebar: [
          {
            text: 'Product Docs',
            items: [
              { text: 'Features', link: '/en/features' },
              { text: 'Model Setup', link: '/en/models' },
              { text: 'Desktop Experience', link: '/en/desktop' }
            ]
          }
        ],
        outline: { label: 'On this page' },
        docFooter: {
          prev: 'Previous',
          next: 'Next'
        }
      }
    }
  },
  themeConfig: {
    logo: '/images/logo.png',
    socialLinks: [
      { icon: 'github', link: 'https://github.com/Radiant303/SpringNote' }
    ],
    search: {
      provider: 'local'
    },
    footer: {
      message: 'Released under the AGPL-3.0 license.',
      copyright: 'Copyright © SpringNote contributors'
    }
  }
})
