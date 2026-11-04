import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Where `npm run dev` sends /api. A local backend by default; set
// VITE_API_TARGET to work against a deployed one instead, which is
// how you look at the panel with real data without running Mongo:
//
//   VITE_API_TARGET=http://3.111.232.213 npm run dev
//
// Remember that is the LIVE database — browse, don't click things
// that change records.
const apiTarget = process.env.VITE_API_TARGET || 'http://localhost:5014'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': { target: apiTarget, changeOrigin: true },
      '/uploads': { target: apiTarget, changeOrigin: true },
      '/socket.io': { target: apiTarget, changeOrigin: true, ws: true }
    }
  }
})
