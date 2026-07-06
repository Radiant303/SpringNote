<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

const { lang } = useData()

const isZh = computed(() => lang.value.startsWith('zh'))

const announcement = computed(() => {
  if (isZh.value) {
    return {
      href: 'https://qm.qq.com/q/dxYq7p4e4w',
      prefix: '预览版',
      text: 'SpringNote，一个面向工作记忆的 AI 便签'
    }
  }

  return {
    href: 'https://qm.qq.com/q/dxYq7p4e4w',
    prefix: 'Early Access',
    text: 'SpringNote, AI notes for work memory'
  }
})
</script>

<template>
  <a class="home-announcement" :href="announcement.href">
    <strong>{{ announcement.prefix }}:</strong>
    <span>{{ announcement.text }}</span>
    <span aria-hidden="true">-&gt;</span>
  </a>
</template>
