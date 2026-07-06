import DefaultTheme from 'vitepress/theme'
import HomeDemo from './components/HomeDemo.vue'
import Layout from './Layout.vue'
import './style.css'

export default {
  extends: DefaultTheme,
  Layout,
  enhanceApp({ app }) {
    app.component('HomeDemo', HomeDemo)
  }
}
