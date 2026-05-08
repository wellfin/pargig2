import axios from 'axios'

const baseURL = import.meta.env.DEV ? '/api' : '/api'

export const api = axios.create({ baseURL })

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('pargig_admin_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

api.interceptors.response.use(
  (r) => r,
  (err) => {
    if (err?.response?.status === 401) {
      localStorage.removeItem('pargig_admin_token')
      if (!location.pathname.endsWith('/login')) location.assign('/admin/login')
    }
    return Promise.reject(err)
  }
)
