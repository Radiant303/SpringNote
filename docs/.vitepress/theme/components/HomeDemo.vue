<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useData } from 'vitepress'

interface OverviewCard {
  eyebrow: string
  accentColor: string
  count: number
  items: string[]
}

const { lang } = useData()
const isZh = computed(() => lang.value.startsWith('zh'))

const copy = computed(() => {
  if (isZh.value) {
    return {
      home: '首页',
      notes: '便签',
      memoryBook: '回忆书',
      settings: '设置',
      more: '更多',
      totalIncome: '累计总收益',
      recentActivity: '最近活跃',
      weekAdded: '本周新增',
      articlesUnit: '篇',
      streak: '连续记录',
      daysUnit: '天',
      lastSync: '上次同步',
      justNow: '刚刚',
      placeholder: '写下你的想法，AI 将自动整理并生成结构化内容...',
      uploadImage: '上传图片',
      addFile: '添加文件',
      mention: '提及功能',
      charUnit: '字',
      submitting: '整理中',
      generate: '智能生成',
      savedPrefix: '已写入当日日报：'
    }
  }

  return {
    home: 'Home',
    notes: 'Notes',
    memoryBook: 'Memory Book',
    settings: 'Settings',
    more: 'More',
    totalIncome: 'Total earnings',
    recentActivity: 'Recently active',
    weekAdded: 'Week',
    articlesUnit: 'notes',
    streak: 'Streak',
    daysUnit: 'days',
    lastSync: 'Sync',
    justNow: 'Just now',
    placeholder: 'Write a thought. AI will organize it...',
    uploadImage: 'Upload image',
    addFile: 'Add file',
    mention: 'Mention tools',
    charUnit: 'chars',
    submitting: 'Organizing',
    generate: 'Generate',
    savedPrefix: 'Saved to daily report:'
  }
})

function createOverview(zh: boolean): OverviewCard[] {
  if (zh) {
    return [
      {
        eyebrow: 'Completed · 完成事项',
        accentColor: '#666666',
        count: 6,
        items: ['重构微服务网关架构路由配置', '整理工程思维决策分析大纲']
      },
      {
        eyebrow: 'Issues · 问题记录',
        accentColor: '#f87171',
        count: 2,
        items: ['Nacos Environment Heartbeat Timeout...', 'Conda Cross-Platform Build Dependency...']
      },
      {
        eyebrow: 'Next Steps · 明日计划',
        accentColor: '#666666',
        count: 4,
        items: ['联调 Cocos 自动化场景切换器', 'Rust Axum 图片渲染服务压测']
      }
    ]
  }

  return [
    {
      eyebrow: 'Completed',
      accentColor: '#666666',
      count: 6,
      items: ['Refactor gateway routing configuration', 'Draft engineering decision outline']
    },
    {
      eyebrow: 'Issues',
      accentColor: '#f87171',
      count: 2,
      items: ['Nacos environment heartbeat timeout...', 'Conda cross-platform dependency...']
    },
    {
      eyebrow: 'Next Steps',
      accentColor: '#666666',
      count: 4,
      items: ['Integrate Cocos scene automation', 'Load test Rust Axum image rendering']
    }
  ]
}

const level = ref(4)
const experiencePercent = ref(75)
const coins = ref(0)
const targetCoins = ref(128)
const totalCoins = ref(14250)
const coinRate = ref(0.12)
const inputText = ref('')
const isSubmitting = ref(false)
const showNotice = ref(false)
const lastSaved = ref('')
const isFocused = ref(false)
const showHeatmap = ref(false)
const ringProgress = ref(0)

const weekCount = ref(18)
const streak = ref(12)
const lastSync = ref(copy.value.justNow)

const overview = ref<OverviewCard[]>(createOverview(isZh.value))

const heatmapDays = 140
const heatmapRows = 7
const heatmapData = ref<{ count: number; level: number; date: string }[]>([])

const heatmapColors = ['#ededed', '#dcfce7', '#bbf7d0', '#86efac', '#4ade80']

function formatDate(offsetDays: number) {
  const d = new Date()
  d.setDate(d.getDate() - offsetDays)
  return d.toISOString().split('T')[0]
}

function generateHeatmapData() {
  const data: { count: number; level: number; date: string }[] = []
  for (let i = 0; i < heatmapDays; i++) {
    const rand = Math.random()
    let count = 0
    let level = 0
    if (rand > 0.95) {
      count = Math.floor(Math.random() * 3) + 8
      level = 4
    } else if (rand > 0.8) {
      count = Math.floor(Math.random() * 3) + 5
      level = 3
    } else if (rand > 0.5) {
      count = Math.floor(Math.random() * 3) + 2
      level = 2
    } else if (rand > 0.2) {
      count = 1
      level = 1
    }
    data.push({ count, level, date: formatDate(heatmapDays - 1 - i) })
  }
  data[heatmapDays - 1].count = 3
  data[heatmapDays - 1].level = 2
  data[heatmapDays - 2].count = 5
  data[heatmapDays - 2].level = 3
  data[heatmapDays - 3].count = 8
  data[heatmapDays - 3].level = 4
  return data
}

const hoveredDay = ref<number | null>(null)
const tooltipPos = ref({ x: 0, y: 0 })
const heatmapWrapRef = ref<HTMLElement | null>(null)

function updateTooltipPosition(index: number) {
  if (!heatmapWrapRef.value) return
  const cells = heatmapWrapRef.value.querySelectorAll('.heatmap-cell')
  const cell = cells[index] as HTMLElement | undefined
  if (!cell) return
  const rect = cell.getBoundingClientRect()
  tooltipPos.value = {
    x: rect.left + rect.width / 2 + window.scrollX,
    y: rect.top + window.scrollY
  }
}

function onCellEnter(index: number) {
  hoveredDay.value = index
  updateTooltipPosition(index)
}

function onCellLeave() {
  hoveredDay.value = null
}

const charCount = computed(() => inputText.value.length)
const canSubmit = computed(() => inputText.value.trim().length > 0 && !isSubmitting.value)

let coinTimer: number | undefined

function formatCoins(value: number) {
  const text = Math.round(value).toString()
  const buffer: string[] = []
  for (let index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 === 0) {
      buffer.push(',')
    }
    buffer.push(text[index])
  }
  return buffer.join('')
}

function formatRate(value: number) {
  return value < 1 ? value.toFixed(2) : value.toFixed(3)
}

function easeOutQuart(x: number) {
  return 1 - Math.pow(1 - x, 4)
}

function animateCounter() {
  const duration = 1600
  let startTime: number | null = null

  function step(timestamp: number) {
    if (!startTime) startTime = timestamp
    const elapsed = timestamp - startTime
    const progress = Math.min(elapsed / duration, 1)
    const eased = easeOutQuart(progress)
    coins.value = Math.floor(eased * targetCoins.value)
    if (progress < 1) {
      requestAnimationFrame(step)
    }
  }

  requestAnimationFrame(step)
}

onMounted(() => {
  heatmapData.value = generateHeatmapData()

  requestAnimationFrame(() => {
    showHeatmap.value = true
  })

  ringProgress.value = experiencePercent.value
  animateCounter()

  coinTimer = window.setInterval(() => {
    totalCoins.value += coinRate.value
  }, 1000)
})

onUnmounted(() => {
  if (coinTimer) window.clearInterval(coinTimer)
})

async function onSubmit() {
  if (!canSubmit.value) return
  isSubmitting.value = true
  showNotice.value = false

  await new Promise(resolve => setTimeout(resolve, 1200))

  const text = inputText.value.trim()
  const summary = text.length > 18 ? text.slice(0, 18) + '...' : text

  if (summary) {
    overview.value[0].items.unshift(summary)
    if (overview.value[0].items.length > 2) overview.value[0].items.pop()
    overview.value[0].count += 1
  }

  const earned = Math.floor(Math.random() * 18) + 6
  coins.value += earned
  targetCoins.value += earned
  totalCoins.value += earned
  weekCount.value += 1

  const now = new Date()
  const dateStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`
  lastSaved.value = `daily_notes/${dateStr}.md`
  lastSync.value = copy.value.justNow
  showNotice.value = true

  inputText.value = ''
  isSubmitting.value = false

  const last = heatmapData.value[heatmapDays - 1]
  last.count += 1
  if (last.level < 4) last.level += 1
}
</script>

<template>
  <div class="home-demo">
    <aside class="app-sidebar">
      <nav class="sidebar-top">
        <a href="#" class="sidebar-item active" :aria-label="copy.home" :title="copy.home">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <rect width="7" height="9" x="3" y="3" rx="1" />
            <rect width="7" height="5" x="14" y="3" rx="1" />
            <rect width="7" height="9" x="14" y="12" rx="1" />
            <rect width="7" height="5" x="3" y="16" rx="1" />
          </svg>
        </a>
        <a href="#" class="sidebar-item" :aria-label="copy.notes" :title="copy.notes">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M16 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V8Z" />
            <path d="M15 3v4" />
            <path d="M15 21h6" />
          </svg>
        </a>
        <a href="#" class="sidebar-item" :aria-label="copy.memoryBook" :title="copy.memoryBook">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 7v14" />
            <path d="M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z" />
          </svg>
        </a>
      </nav>
      <a href="#" class="sidebar-item" :aria-label="copy.settings" :title="copy.settings">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915" />
          <circle cx="12" cy="12" r="3" />
        </svg>
      </a>
    </aside>

    <main class="app-main">
      <header class="app-header">
        <h1>{{ copy.home }}</h1>
        <button class="icon-button" :aria-label="copy.more">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="1" />
            <circle cx="19" cy="12" r="1" />
            <circle cx="5" cy="12" r="1" />
          </svg>
        </button>
      </header>

      <section class="hero-card">
        <div class="hero-left">
          <div class="level-ring">
            <span class="level-label">Level {{ String(level).padStart(2, '0') }}</span>
            <div class="ring-wrap">
              <svg class="ring-svg" viewBox="0 0 36 36">
                <path
                  class="ring-track"
                  stroke-width="2.5"
                  stroke="currentColor"
                  fill="none"
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                />
                <path
                  class="ring-progress"
                  :stroke-dasharray="`${ringProgress}, 100`"
                  stroke-width="2.5"
                  stroke-linecap="round"
                  stroke="currentColor"
                  fill="none"
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                />
              </svg>
              <span class="ring-text">{{ experiencePercent }}%</span>
            </div>
          </div>

          <div class="income-summary">
            <span class="income-label">Earnings Today</span>
            <div class="income-row">
              <span class="income-value">{{ formatCoins(coins) }}</span>
              <span class="income-rate">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                  <polyline points="22 7 13.5 15.5 8.5 10.5 2 17" />
                  <polyline points="16 7 22 7 22 13" />
                </svg>
                +{{ formatRate(coinRate) }} c/s
              </span>
            </div>
            <span class="income-total">
              {{ copy.totalIncome }} <strong>{{ formatCoins(totalCoins) }}</strong> coins
            </span>
          </div>
        </div>

        <div class="hero-right">
          <div class="activity-header">
            <span>Activity Input</span>
            <span class="activity-status">{{ copy.recentActivity }}</span>
          </div>
          <div ref="heatmapWrapRef" class="heatmap">
            <div
              v-for="i in heatmapDays"
              :key="i"
              class="heatmap-cell-wrap"
              :class="{ visible: showHeatmap }"
              :style="{ animationDelay: `${300 + (i - 1) * 4}ms` }"
            >
              <div
                class="heatmap-cell"
                :style="{ backgroundColor: heatmapColors[heatmapData[i - 1]?.level || 0] }"
                @mouseenter="onCellEnter(i - 1)"
                @mouseleave="onCellLeave"
              />
            </div>
            <div
              v-if="hoveredDay !== null"
              class="heatmap-tooltip"
              :style="{ left: `${tooltipPos.x}px`, top: `${tooltipPos.y - 8}px` }"
            >
              <template v-if="heatmapData[hoveredDay]?.count === 0">
                <span class="tooltip-muted">No contributions on</span>
                <span class="tooltip-date">{{ heatmapData[hoveredDay]?.date }}</span>
              </template>
              <template v-else>
                <span class="tooltip-count">{{ heatmapData[hoveredDay]?.count }} {{ heatmapData[hoveredDay]?.count === 1 ? 'commit' : 'commits' }}</span>
                <span class="tooltip-muted">on</span>
                <span class="tooltip-date">{{ heatmapData[hoveredDay]?.date }}</span>
              </template>
            </div>
          </div>
          <div class="activity-metrics">
            <span>{{ copy.weekAdded }}: <strong class="metric-primary">{{ weekCount }} {{ copy.articlesUnit }}</strong></span>
            <span>{{ copy.streak }}: <strong class="metric-primary">{{ streak }} {{ copy.daysUnit }}</strong></span>
            <span>{{ copy.lastSync }}: <strong class="metric-muted">{{ lastSync }}</strong></span>
          </div>
        </div>
      </section>

      <section class="capture-card" :class="{ focused: isFocused }">
        <textarea
          v-model="inputText"
          :placeholder="copy.placeholder"
          rows="4"
          @focus="isFocused = true"
          @blur="isFocused = false"
          @keydown.ctrl.enter="onSubmit"
          @keydown.meta.enter="onSubmit"
        />
        <div class="capture-toolbar">
          <div class="toolbar-tools">
            <button class="tool-button" :title="copy.uploadImage">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <rect width="18" height="18" x="3" y="3" rx="2" />
                <circle cx="9" cy="9" r="2" />
                <path d="M21 15 17.914 11.914C17.133 11.133 15.867 11.133 15.086 11.914L6 21" />
              </svg>
            </button>
            <button class="tool-button" :title="copy.addFile">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M16 6 7.586 14.586C6.805 15.367 6.805 16.633 7.586 17.414C8.367 18.195 9.633 18.195 10.414 17.414L18.828 8.828C20.39 7.266 20.39 4.734 18.828 3.172C17.266 1.61 14.734 1.61 13.172 3.172L4.793 11.723C2.45 14.066 2.45 17.864 4.793 20.207C7.136 22.55 10.934 22.55 13.277 20.207L21.656 11.656" />
              </svg>
            </button>
            <button class="tool-button" :title="copy.mention">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="4" />
                <path d="M16 8 16 13C16 14.657 17.343 16 19 16C20.657 16 22 14.657 22 13L22 12C22 6.477 17.523 2 12 2C6.477 2 2 6.477 2 12C2 17.523 6.477 22 12 22C14.197 22 16.224 21.294 17.875 20.097" />
              </svg>
            </button>
          </div>
          <div class="toolbar-actions">
            <span class="char-count">{{ charCount }} {{ copy.charUnit }}</span>
            <button class="generate-button" :class="{ inactive: !canSubmit && !isSubmitting }" @click="onSubmit">
              <span>{{ isSubmitting ? copy.submitting : copy.generate }}</span>
              <svg v-if="!isSubmitting" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z" />
                <path d="M5 3v4" />
                <path d="M19 17v4" />
                <path d="M3 5h4" />
                <path d="M17 19h4" />
              </svg>
              <svg v-else class="spinner" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                <path d="M21 12a9 9 0 11-6.219-8.56" />
              </svg>
            </button>
          </div>
        </div>
      </section>

      <div v-if="showNotice" class="notice-banner">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M22 11.08V12a10 10 0 11-5.93-9.14" />
          <polyline points="22 4 12 14.01 9 11.01" />
        </svg>
        <span>{{ copy.savedPrefix }} {{ lastSaved }}</span>
      </div>

      <section class="overview-grid">
        <div v-for="(card, idx) in overview" :key="idx" class="overview-card">
          <div class="overview-card-inner">
            <div class="overview-card-content">
              <span class="overview-eyebrow" :style="{ color: card.accentColor }">{{ card.eyebrow }}</span>
              <div class="overview-items">
                <p v-if="card.items[0]">{{ card.items[0] }}</p>
                <p v-if="card.items[1]" class="secondary">{{ card.items[1] }}</p>
              </div>
            </div>
            <span class="overview-count">{{ String(card.count).padStart(2, '0') }}</span>
          </div>
        </div>
      </section>
    </main>
  </div>
</template>

<style scoped>
.home-demo {
  background: #fcfcfc;
  color: #171717;
  display: flex;
  font-family: 'Segoe UI', Inter, 'SF Pro Display', -apple-system, BlinkMacSystemFont, Roboto, 'PingFang SC', sans-serif;
  min-height: 640px;
  overflow: hidden;
  -webkit-font-smoothing: antialiased;
}

.app-sidebar {
  align-items: center;
  background: #fcfcfc;
  display: flex;
  flex-direction: column;
  flex-shrink: 0;
  height: auto;
  justify-content: space-between;
  padding: 28px 16px;
  user-select: none;
  width: 80px;
}

.sidebar-top {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.sidebar-item {
  align-items: center;
  border-radius: 12px;
  color: #666666;
  display: flex;
  height: 40px;
  justify-content: center;
  transition: background 160ms ease, color 160ms ease;
  width: 40px;
}

.sidebar-item:hover {
  background: #f5f5f5;
  color: #171717;
}

.sidebar-item.active {
  background: #e2e2e2;
  color: #171717;
}

.app-main {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 32px;
  min-width: 0;
  overflow-y: auto;
  padding: 32px 48px 40px;
}

.app-main::-webkit-scrollbar {
  display: none;
}

.app-main {
  -ms-overflow-style: none;
  scrollbar-width: none;
}

.app-header {
  align-items: center;
  display: flex;
  justify-content: space-between;
  user-select: none;
}

.app-header h1 {
  color: #171717;
  font-size: 18px;
  font-weight: 600;
  letter-spacing: -0.2px;
  line-height: 1.35;
  margin: 0;
}

.icon-button {
  align-items: center;
  background: transparent;
  border: none;
  border-radius: 10px;
  color: #666666;
  cursor: pointer;
  display: flex;
  height: 34px;
  justify-content: center;
  padding: 8px;
  transition: background 160ms ease, color 160ms ease;
  width: 34px;
}

.icon-button:hover {
  background: #ededed;
  color: #4f4f4f;
}

.hero-card {
  align-items: center;
  background: #ffffff;
  border: 1px solid rgba(224, 224, 224, 0.6);
  border-radius: 26px;
  box-shadow: 0 4px 30px rgba(0, 0, 0, 0.02), 0 1px 3px rgba(0, 0, 0, 0.02);
  display: flex;
  gap: 48px;
  justify-content: space-between;
  padding: 32px;
}

.hero-left {
  align-items: center;
  display: flex;
  flex: 1 1 0;
  gap: 48px;
  min-width: 0;
}

.level-ring {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 8px;
  user-select: none;
}

.level-label {
  color: #666666;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 1px;
  line-height: 1.5;
  text-transform: uppercase;
}

.ring-wrap {
  align-items: center;
  display: flex;
  height: 64px;
  justify-content: center;
  position: relative;
  width: 64px;
}

.ring-svg {
  color: #666666;
  height: 64px;
  left: 0;
  position: absolute;
  top: 0;
  transform: rotate(-90deg);
  width: 64px;
}

.ring-track {
  color: #ededed;
}

.ring-progress {
  transition: none;
}

.ring-text {
  color: #4f4f4f;
  font-size: 12px;
  font-weight: 700;
  line-height: 1;
  position: relative;
  z-index: 1;
}

.income-summary {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.income-label {
  color: #8a8a8a;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 1px;
  line-height: 1.5;
  margin-bottom: 4px;
  text-transform: uppercase;
  user-select: none;
}

.income-row {
  align-items: baseline;
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}

.income-value {
  color: #171717;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 56px;
  font-weight: 700;
  letter-spacing: -3.2px;
  line-height: 1;
  font-variant-numeric: tabular-nums;
}

.income-rate {
  align-items: center;
  background: #ecfdf5;
  border-radius: 6px;
  color: #059669;
  display: inline-flex;
  font-size: 12px;
  font-weight: 600;
  gap: 4px;
  padding: 3px 8px;
  user-select: none;
  font-variant-numeric: tabular-nums;
}

.income-total {
  color: #8a8a8a;
  font-size: 12px;
  letter-spacing: 0.1px;
  line-height: 1.55;
  margin-top: 8px;
  user-select: none;
}

.income-total strong {
  color: #666666;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-weight: 600;
}

.hero-right {
  border-left: 1px solid #ededed;
  display: flex;
  flex: 0 0 auto;
  flex-direction: column;
  gap: 12px;
  min-width: 0;
  padding-left: 32px;
  width: 392px;
}

.activity-header {
  align-items: center;
  display: flex;
  font-size: 11px;
  font-weight: 500;
  justify-content: space-between;
  letter-spacing: 1px;
  line-height: 1.5;
  text-transform: uppercase;
  user-select: none;
}

.activity-header span:first-child {
  color: #666666;
}

.activity-status {
  color: #10b981;
  font-weight: 500;
  letter-spacing: 0;
  text-transform: none;
}

.heatmap {
  display: grid;
  gap: 3px;
  grid-auto-flow: column;
  grid-template-rows: repeat(7, 13px);
  padding-bottom: 6px;
  position: relative;
  width: max-content;
  z-index: 10;
}

.heatmap-cell-wrap {
  opacity: 0;
  transform: scale(0.4);
}

.heatmap-cell-wrap.visible {
  animation: cellIn 0.3s cubic-bezier(0.33, 1, 0.68, 1) both;
}

.heatmap-cell {
  border-radius: 2.5px;
  cursor: pointer;
  height: 13px;
  transition: transform 150ms ease;
  width: 13px;
}

.heatmap-cell:hover {
  transform: scale(1.1);
  z-index: 20;
}

.heatmap-tooltip {
  background: #ffffff;
  border: 1px solid #ededed;
  border-radius: 8px;
  box-shadow: 0 8px 18px rgba(0, 0, 0, 0.15);
  color: #262626;
  font-size: 11px;
  font-weight: 500;
  line-height: 1.2;
  padding: 6px 10px;
  pointer-events: none;
  position: fixed;
  transform: translate(-50%, -100%);
  white-space: nowrap;
  z-index: 1000;
}

.tooltip-muted {
  color: #666666;
}

.tooltip-count {
  color: #171717;
  font-weight: 700;
}

.tooltip-date {
  color: #4f4f4f;
  font-weight: 600;
}

.activity-metrics {
  color: #666666;
  display: flex;
  flex-wrap: wrap;
  font-size: 12px;
  gap: 18px;
  line-height: 1.55;
  margin-top: 4px;
  user-select: none;
}

.activity-metrics span {
  white-space: nowrap;
}

.activity-metrics strong {
  font-weight: 600;
}

.activity-metrics strong.metric-primary {
  color: #3a3a3a;
}

.activity-metrics strong.metric-muted {
  color: #666666;
}

.capture-card {
  background: rgba(245, 245, 245, 0.6);
  border: 1px solid rgba(224, 224, 224, 0.6);
  border-radius: 16px;
  display: flex;
  flex-direction: column;
  padding: 16px;
  transition: background 160ms ease, border-color 160ms ease;
}

.capture-card.focused {
  background: rgba(245, 245, 245, 0.9);
  border-color: rgba(207, 207, 207, 0.8);
}

textarea {
  background: transparent;
  border: none;
  color: #262626;
  font-family: inherit;
  font-size: 14px;
  line-height: 1.625;
  min-height: 96px;
  outline: none;
  resize: none;
  width: 100%;
}

textarea::placeholder {
  color: rgba(138, 138, 138, 0.8);
}

.capture-toolbar {
  align-items: center;
  border-top: 1px solid rgba(237, 237, 237, 0.5);
  display: flex;
  justify-content: space-between;
  margin-top: 10px;
  padding-top: 8px;
  user-select: none;
}

.toolbar-tools {
  display: flex;
  gap: 4px;
}

.tool-button {
  align-items: center;
  background: transparent;
  border: none;
  border-radius: 12px;
  color: #666666;
  cursor: pointer;
  display: flex;
  height: 32px;
  justify-content: center;
  padding: 8px;
  position: relative;
  transition: color 160ms ease;
  width: 32px;
}

.tool-button::before {
  background: #ffffff;
  border-radius: 12px;
  content: '';
  inset: 0;
  opacity: 0;
  position: absolute;
  transition: opacity 160ms cubic-bezier(0.33, 1, 0.68, 1);
  z-index: 0;
}

.tool-button:hover {
  color: #4f4f4f;
}

.tool-button:hover::before {
  opacity: 1;
}

.tool-button svg {
  position: relative;
  z-index: 1;
}

.toolbar-actions {
  align-items: center;
  display: flex;
  gap: 18px;
}

.char-count {
  color: #666666;
  font-size: 12px;
  line-height: 1.55;
}

.generate-button {
  align-items: center;
  background: #171717;
  border: none;
  border-radius: 14px;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
  color: #ffffff;
  cursor: pointer;
  display: inline-flex;
  font-size: 12px;
  font-weight: 500;
  gap: 6px;
  height: 28px;
  line-height: 1.333;
  padding: 6px 16px;
  transition: background 150ms ease;
}

.generate-button:hover:not(.inactive) {
  background: #262626;
}

.generate-button.inactive {
  cursor: default;
}

.generate-button svg {
  color: #34d399;
  flex-shrink: 0;
}

.spinner {
  animation: spin 1s linear infinite;
}

.notice-banner {
  align-items: center;
  background: #ecfdf5;
  border: 1px solid #d1fae5;
  border-radius: 16px;
  color: #047857;
  display: flex;
  gap: 10px;
  font-size: 13px;
  line-height: 1.55;
  padding: 12px 16px;
}

.notice-banner span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.overview-grid {
  display: grid;
  gap: 24px;
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.overview-card {
  background: #ffffff;
  border: 1px solid rgba(224, 224, 224, 0.6);
  border-radius: 16px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  padding: 28px;
  user-select: none;
}

.overview-card-inner {
  align-items: center;
  display: flex;
  flex: 1;
  justify-content: space-between;
  min-width: 0;
}

.overview-card-content {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-width: 0;
}

.overview-eyebrow {
  font-size: 10px;
  font-weight: 500;
  letter-spacing: 1px;
  line-height: 1.5;
  text-transform: uppercase;
}

.overview-items {
  display: flex;
  flex-direction: column;
  gap: 4px;
  height: 36px;
}

.overview-items p {
  color: #4f4f4f;
  font-size: 12px;
  line-height: 1.333;
  margin: 0;
  max-width: 180px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.overview-items p.secondary {
  color: #666666;
}

.overview-count {
  color: #171717;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 36px;
  font-weight: 600;
  letter-spacing: -0.9px;
  line-height: 1;
  margin-left: 18px;
  font-variant-numeric: tabular-nums;
}

@keyframes cellIn {
  0% {
    opacity: 0;
    transform: scale(0.4);
  }
  100% {
    opacity: 1;
    transform: scale(1);
  }
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

@media (max-width: 1080px) {
  .app-main {
    padding: 28px 32px 36px;
  }

  .hero-card {
    gap: 32px;
    padding: 28px;
  }

  .hero-left {
    gap: 32px;
  }

  .hero-right {
    padding-left: 24px;
    width: 340px;
  }
}

@media (max-width: 960px) {
  .hero-card {
    align-items: flex-start;
    flex-direction: column;
    gap: 28px;
  }

  .hero-right {
    border-left: none;
    padding-left: 0;
    width: 100%;
  }

  .hero-left {
    gap: 32px;
    width: 100%;
  }

  .income-value {
    font-size: 42px;
  }

  .overview-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 640px) {
  .home-demo {
    flex-direction: column;
    min-height: auto;
  }

  .app-sidebar {
    flex-direction: row;
    height: auto;
    justify-content: center;
    padding: 16px;
    width: 100%;
  }

  .sidebar-top {
    flex-direction: row;
  }

  .app-main {
    gap: 24px;
    padding: 20px;
  }

  .hero-card {
    padding: 22px;
  }

  .hero-left {
    flex-direction: column;
    gap: 24px;
  }

  .capture-toolbar {
    align-items: flex-start;
    flex-direction: column;
    gap: 10px;
  }

  .overview-card {
    padding: 22px;
  }
}

@media (prefers-reduced-motion: reduce) {
  .heatmap-cell-wrap.visible {
    animation: none;
    opacity: 1;
    transform: scale(1);
  }

  .ring-progress {
    transition: none;
  }

  .spinner {
    animation: none;
  }
}
</style>
