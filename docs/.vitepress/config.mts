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
          { text: '文档', link: '/guide/quick-start' },
          { text: 'GitHub', link: 'https://github.com/Radiant303/SpringNote' }
        ],
        sidebar: [
          {
            text: '基础指南',
            items: [
              { text: '快速入门', link: '/guide/quick-start' },
              { text: '系统要求', link: '/guide/system' },
              { text: '隐私与安全', link: '/guide/privacy' },
              { text: '更新与版本', link: '/guide/updates' }
            ]
          },
          {
            text: '使用指南',
            items: [
              {
                text: '首页',
                items: [
                  { text: '数据概览', link: '/guide/home-data' },
                  { text: '快速输入框', link: '/guide/home-input' },
                  { text: '首页三栏', link: '/guide/home-columns' }
                ]
              },
              {
                text: '笔记本',
                items: [
                  { text: '日报', link: '/guide/daily' },
                  { text: '周报', link: '/guide/weekly' },
                  { text: '月报', link: '/guide/monthly' },
                  { text: '搜索笔记', link: '/guide/note-search' },
                  { text: 'AI 实时补全', link: '/guide/note-completion' },
                  { text: 'Markdown 渲染', link: '/guide/markdown' },
                  { text: '工作区模式', link: '/guide/workspace' }
                ]
              },
              {
                text: '回忆书',
                items: [
                  { text: 'AI 能力介绍', link: '/guide/memory-ai' },
                  { text: 'AI 思考模式', link: '/guide/memory-thinking' },
                  { text: '开启新对话', link: '/guide/memory-conversation' }
                ]
              },
              {
                text: '组件',
                items: [
                  { text: '组件设置', link: '/guide/widget-settings' },
                  { text: '组件壁纸', link: '/guide/widget-wallpaper' }
                ]
              },
              {
                text: '设置',
                items: [
                  {
                    text: '偏好设置',
                    link: '/guide/settings'
                  },
                  {
                    text: '供应商',
                    link: '/guide/providers'
                  },
                  {
                    text: '默认模型',
                    link: '/guide/ai'
                  },
                  {
                    text: '快捷键',
                    link: '/guide/shortcuts'
                  },
                  {
                    text: '云同步',
                    link: '/guide/data'
                  },
                  {
                    text: '存储管理',
                    link: '/guide/attachments'
                  },
                  {
                    text: '统计',
                    link: '/guide/statistics'
                  },
                  { text: '关于', link: '/guide/about' }
                ]
              }
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
          { text: 'Guide', link: '/en/guide/quick-start' },
          { text: 'Features', link: '/en/features' },
          { text: 'Models', link: '/en/models' },
          { text: 'Desktop', link: '/en/desktop' },
          { text: 'GitHub', link: 'https://github.com/Radiant303/SpringNote' }
        ],
        sidebar: [
          {
            text: 'Getting Started',
            items: [
              { text: 'Quick Start', link: '/en/guide/quick-start' },
              { text: 'System Requirements', link: '/en/guide/system' },
              { text: 'Privacy & Security', link: '/en/guide/privacy' },
              { text: 'Updates & Versions', link: '/en/guide/updates' }
            ]
          },
          {
            text: 'Usage Guide',
            items: [
              {
                text: 'Home',
                items: [
                  { text: 'Data Overview', link: '/en/guide/home-data' },
                  { text: 'Quick Input', link: '/en/guide/home-input' },
                  { text: 'Home Columns', link: '/en/guide/home-columns' }
                ]
              },
              {
                text: 'Notebook',
                items: [
                  { text: 'Daily Notes', link: '/en/guide/daily' },
                  { text: 'Weekly Notes', link: '/en/guide/weekly' },
                  { text: 'Monthly Notes', link: '/en/guide/monthly' },
                  { text: 'Search Notes', link: '/en/guide/note-search' },
                  { text: 'AI Completion', link: '/en/guide/note-completion' },
                  { text: 'Markdown Rendering', link: '/en/guide/markdown' },
                  { text: 'Workspace Mode', link: '/en/guide/workspace' }
                ]
              },
              {
                text: 'Memory Book',
                items: [
                  { text: 'AI Capabilities', link: '/en/guide/memory-ai' },
                  { text: 'Thinking Mode', link: '/en/guide/memory-thinking' },
                  { text: 'New Conversation', link: '/en/guide/memory-conversation' }
                ]
              },
              {
                text: 'Widget',
                items: [
                  { text: 'Widget Settings', link: '/en/guide/widget-settings' },
                  { text: 'Widget Wallpaper', link: '/en/guide/widget-wallpaper' }
                ]
              },
              {
                text: 'Settings',
                items: [
                  { text: 'Preferences', link: '/en/guide/settings' },
                  { text: 'Providers', link: '/en/guide/providers' },
                  { text: 'Default Models', link: '/en/guide/ai' },
                  { text: 'Shortcuts', link: '/en/guide/shortcuts' },
                  { text: 'Cloud Sync', link: '/en/guide/data' },
                  { text: 'Storage Management', link: '/en/guide/attachments' },
                  { text: 'Statistics', link: '/en/guide/statistics' },
                  { text: 'About', link: '/en/guide/about' }
                ]
              }
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
