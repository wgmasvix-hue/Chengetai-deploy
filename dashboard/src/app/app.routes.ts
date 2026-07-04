import { Routes } from '@angular/router';

import { Dashboard } from './pages/dashboard/dashboard';
import { Deployments } from './pages/deployments/deployments';
import { NewDeployment } from './pages/new-deployment/new-deployment';
import { Server } from './pages/server/server';
import { Backups } from './pages/backups/backups';
import { Settings } from './pages/settings/settings';

export const routes: Routes = [
  { path: '', component: Dashboard },
  { path: 'deployments', component: Deployments },
  { path: 'new-deployment', component: NewDeployment },
  { path: 'server', component: Server },
  { path: 'backups', component: Backups },
  { path: 'settings', component: Settings },
  { path: '**', redirectTo: '' }
];
