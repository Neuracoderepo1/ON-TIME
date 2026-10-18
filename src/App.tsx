import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { AuthProvider } from './auth/AuthProvider';
import { MemberLayout, PublicLayout } from './components/Layout';
import { ProtectedRoute } from './components/ProtectedRoute';
import { Landing } from './pages/Landing';
import { SignIn } from './pages/SignIn';
import { SignUp } from './pages/SignUp';
import { AuthCallback } from './pages/AuthCallback';
import { Dashboard } from './pages/Dashboard';
import { Rounds } from './pages/Rounds';
import { Rewards } from './pages/Rewards';
import { Activity } from './pages/Activity';
import { Account } from './pages/Account';
import { Admin } from './pages/Admin';
import { Eligibility, NotFound, Privacy, RewardConditions, Terms } from './pages/Legal';
import { configError } from './lib/supabase';

export default function App() {
  if (configError) {
    return (
      <div className="container narrow" role="alert">
        <h1>Configuration error</h1>
        <p>{configError}</p>
      </div>
    );
  }
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route element={<PublicLayout />}>
            <Route index element={<Landing />} />
            <Route path="signin" element={<SignIn />} />
            <Route path="signup" element={<SignUp />} />
            <Route path="auth/callback" element={<AuthCallback />} />
            <Route path="terms" element={<Terms />} />
            <Route path="privacy" element={<Privacy />} />
            <Route path="eligibility" element={<Eligibility />} />
            <Route path="reward-conditions" element={<RewardConditions />} />
            <Route path="*" element={<NotFound />} />
          </Route>
          <Route element={<ProtectedRoute />}>
            <Route path="app" element={<MemberLayout />}>
              <Route index element={<Dashboard />} />
              <Route path="rounds" element={<Rounds />} />
              <Route path="rewards" element={<Rewards />} />
              <Route path="activity" element={<Activity />} />
              <Route path="account" element={<Account />} />
              <Route path="admin" element={<Admin />} />
            </Route>
          </Route>
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
