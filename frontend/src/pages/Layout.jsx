import { NavLink, Outlet, useNavigate } from 'react-router-dom'

export default function Layout() {
  const nav = useNavigate()
  const admin = JSON.parse(localStorage.getItem('pargig_admin') || '{}')

  const logout = () => {
    localStorage.removeItem('pargig_admin_token')
    localStorage.removeItem('pargig_admin')
    nav('/login', { replace: true })
  }

  return (
    <div className="layout">
      <aside className="sidebar">
        <h1>PARGIG</h1>
        <nav className="nav">
          <NavLink to="/" end>Dashboard</NavLink>
          <NavLink to="/users">Users</NavLink>
          <NavLink to="/jobs">Jobs</NavLink>
          <NavLink to="/payments">Payments</NavLink>
          <NavLink to="/disputes">Disputes</NavLink>
          <NavLink to="/reports">Reports</NavLink>
        </nav>
      </aside>
      <main className="main">
        <div className="topbar">
          <h2>Welcome, {admin.name || 'Admin'}</h2>
          <button className="btn secondary" onClick={logout}>Logout</button>
        </div>
        <Outlet />
      </main>
    </div>
  )
}
