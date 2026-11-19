import { Routes, Route, Navigate } from 'react-router-dom'
import Login from './pages/Login.jsx'
import Layout from './pages/Layout.jsx'
import Guard from './components/Guard.jsx'
import Dashboard from './pages/Dashboard.jsx'
import Users from './pages/Users.jsx'
import UserDetail from './pages/UserDetail.jsx'
import Verifications from './pages/Verifications.jsx'
import SupportChat from './pages/SupportChat.jsx'
import Jobs from './pages/Jobs.jsx'
import JobDetail from './pages/JobDetail.jsx'
import Payments from './pages/Payments.jsx'
import Issues from './pages/Issues.jsx'
import IssueDetail from './pages/IssueDetail.jsx'
import Analytics from './pages/Analytics.jsx'
import Reports from './pages/Reports.jsx'
import Settings from './pages/Settings.jsx'
import './App.css'

const isAuthed = () => !!localStorage.getItem('pargig_admin_token')

const Protected = ({ children }) =>
  isAuthed() ? children : <Navigate to="/login" replace />

/**
 * Every page names the permission that opens it.
 *
 * Guard renders inside Layout, which is what supplies the signed-in
 * admin's permissions, so these are not route-level redirects — the
 * shell stays up and the content area explains itself. The index
 * route redirects instead, because a "no access" card is a poor home
 * page for someone who has other pages to go to.
 *
 * Settings has no Guard of its own: it is three tabs behind two
 * different permissions, so the page draws only the ones the role can
 * use and says so when that is none.
 */
export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/"
        element={
          <Protected>
            <Layout />
          </Protected>
        }
      >
        <Route
          index
          element={
            <Guard perm="dashboard" label="the Dashboard" redirect>
              <Dashboard />
            </Guard>
          }
        />
        <Route
          path="users"
          element={<Guard perm="users" label="Users"><Users /></Guard>}
        />
        <Route
          path="users/:id"
          element={<Guard perm="users" label="Users"><UserDetail /></Guard>}
        />
        <Route
          path="verifications"
          element={
            <Guard perm="verifications" label="Verifications">
              <Verifications />
            </Guard>
          }
        />
        <Route
          path="support"
          element={
            <Guard perm="support" label="Support Chat"><SupportChat /></Guard>
          }
        />
        <Route
          path="jobs"
          element={<Guard perm="jobs" label="Jobs"><Jobs /></Guard>}
        />
        <Route
          path="jobs/:id"
          element={<Guard perm="jobs" label="Jobs"><JobDetail /></Guard>}
        />
        <Route
          path="payments"
          element={<Guard perm="payments" label="Payments"><Payments /></Guard>}
        />
        <Route
          path="issues"
          element={<Guard perm="disputes" label="Disputes"><Issues /></Guard>}
        />
        <Route
          path="issues/:id"
          element={<Guard perm="disputes" label="Disputes"><IssueDetail /></Guard>}
        />
        <Route
          path="analytics"
          element={<Guard perm="analytics" label="Analytics"><Analytics /></Guard>}
        />
        <Route
          path="reports"
          element={<Guard perm="reports" label="Reports"><Reports /></Guard>}
        />
        <Route path="settings" element={<Settings />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
