import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { Skeleton } from './States';

export function ProtectedRoute() {
  const { session, loading } = useAuth();
  const loc = useLocation();
  if (loading)
    return (
      <div className="container">
        <Skeleton lines={4} />
      </div>
    );
  if (!session) return <Navigate to="/signin" replace state={{ from: loc.pathname }} />;
  return <Outlet />;
}
