<script setup lang="ts">
import DefaultTheme from 'vitepress/theme'
import HomeAnnouncement from './components/HomeAnnouncement.vue'

const { Layout } = DefaultTheme
</script>

<template>
  <Layout>
    <template #home-hero-before>
      <HomeAnnouncement />
    </template>
  </Layout>
</template>
