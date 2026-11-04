import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import './index.css'
// Every theme is bundled; only the one named by THEME is applied,
// because each file is scoped to its own [data-theme] selector. They
// are a few hundred bytes each, and having them all present is what
// lets the theme be switched from one line instead of an import.
import './themes/studio.css'
import './themes/slate.css'
import './themes/midnight.css'
import './themes/clay.css'
import './themes/dusk.css'
import { THEME } from './theme'
import App from './App.jsx'

// Set before the first render so the panel never paints in one theme
// and then flips to another.
if (THEME && THEME !== 'pargig') {
  document.documentElement.dataset.theme = THEME
}

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>,
)
