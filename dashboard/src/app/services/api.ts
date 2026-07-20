import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { resolveApiUrl } from './runtime-config';
import {
  DashboardStats, ServerInfo, Deployment, Plugin, Job, User, NewDeploymentRequest,
} from '../models/api.models';

@Injectable({ providedIn: 'root' })
export class ApiService {
  private http = inject(HttpClient);

  // Resolved at runtime from public/config.js so one build can point at
  // any backend (edit config.js on the host, no rebuild).
  private apiUrl = resolveApiUrl();

  // ── Dashboard / catalogue ──
  getHealth() { return this.http.get<{ status: string; version: string }>(`${this.apiUrl}/health`); }
  getDashboard() { return this.http.get<DashboardStats>(`${this.apiUrl}/dashboard`); }
  getPlugins() { return this.http.get<Plugin[]>(`${this.apiUrl}/plugins`); }

  // ── Servers ──
  getServers() { return this.http.get<ServerInfo[]>(`${this.apiUrl}/servers`); }
  addServer(server: Partial<ServerInfo>) { return this.http.post<ServerInfo>(`${this.apiUrl}/servers`, server); }
  deleteServer(id: string) { return this.http.delete<void>(`${this.apiUrl}/servers/${id}`); }

  // ── Deployments ──
  getDeployments() { return this.http.get<Deployment[]>(`${this.apiUrl}/deployments`); }
  createDeployment(body: NewDeploymentRequest) {
    return this.http.post<{ jobId: string; deployment: string }>(`${this.apiUrl}/deployments`, body);
  }
  deploymentAction(name: string, action: string) {
    return this.http.post<{ jobId: string }>(`${this.apiUrl}/deployments/${name}/actions/${action}`, {});
  }
  deploymentStatus(name: string) {
    return this.http.get<{ deployment: string; output: string }>(`${this.apiUrl}/deployments/${name}/status`);
  }
  startManager(name: string) {
    return this.http.post<{ url: string; port: number; running: boolean }>(
      `${this.apiUrl}/deployments/${name}/manager`, {});
  }
  deleteDeployment(name: string, purge = false) {
    return this.http.delete<{ jobId: string }>(`${this.apiUrl}/deployments/${name}?purge=${purge}`);
  }

  // ── Jobs ──
  getJob(id: string, since = 0) {
    return this.http.get<Job>(`${this.apiUrl}/jobs/${id}?since=${since}`);
  }

  // ── Users ──
  getUsers() { return this.http.get<User[]>(`${this.apiUrl}/users`); }
  createUser(body: { email: string; password: string; role: string }) {
    return this.http.post<User>(`${this.apiUrl}/users`, body);
  }
  updateUser(id: string, patch: Partial<{ role: string; password: string }>) {
    return this.http.patch<User>(`${this.apiUrl}/users/${id}`, patch);
  }
  deleteUser(id: string) { return this.http.delete<void>(`${this.apiUrl}/users/${id}`); }

  // ── Account ──
  changePassword(currentPassword: string, newPassword: string) {
    return this.http.post<{ ok: boolean }>(`${this.apiUrl}/auth/change-password`, { currentPassword, newPassword });
  }
}
