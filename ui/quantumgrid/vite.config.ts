import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  // The app is hosted below /quantumgrid/ in the router's /www tree.
  base: './',
  plugins: [react()],
})
