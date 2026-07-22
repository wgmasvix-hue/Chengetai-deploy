import { Routes } from '@angular/router';

import { MainLayout } from './layouts/main-layout/main-layout';
import { Login } from './pages/login/login';
import { Dashboard } from './pages/dashboard/dashboard';
import { Deployments } from './pages/deployments/deployments';
import { NewDeployment } from './pages/new-deployment/new-deployment';
import { Server } from './pages/server/server';
import { Fleet } from './pages/fleet/fleet';
import { Backups } from './pages/backups/backups';
import { Settings } from './pages/settings/settings';
import { Users } from './pages/users/users';
import { authGuard } from './guards/auth.guard';

export const routes: Routes = [
  { path: 'login', component: Login },
  {
    path: '',
    component: MainLayout,
    canActivate: [authGuard],
    children: [
      { path: '', component: Dashboard },
      { path: 'deployments', component: Deployments },
      { path: 'new-deployment', component: NewDeployment },
      { path: 'server', component: Server },
      { path: 'fleet', component: Fleet },
      { path: 'backups', component: Backups },
      { path: 'users', component: Users },
      { path: 'settings', component: Settings },
    ],
  },
  { path: '**', redirectTo: '' },
];
