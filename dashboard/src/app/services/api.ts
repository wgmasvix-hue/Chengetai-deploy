import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../environments/environment';
import { DashboardStats, ServerInfo, Deployment, Plugin } from '../models/api.models';

@Injectable({ providedIn: 'root' })
export class ApiService {
  private http = inject(HttpClient);

  // Same host the dashboard is served from, API on port 3000 — so the
  // dashboard works on any server without a hardcoded address.
  private apiUrl = environment.apiUrl
    || `${window.location.protocol}//${window.location.hostname}:3000/api`;

  getDashboard() {
    return this.http.get<DashboardStats>(`${this.apiUrl}/dashboard`);
  }

  getServers() {
    return this.http.get<ServerInfo[]>(`${this.apiUrl}/servers`);
  }

  addServer(server: Partial<ServerInfo>) {
    return this.http.post<ServerInfo>(`${this.apiUrl}/servers`, server);
  }

  deleteServer(id: string) {
    return this.http.delete<void>(`${this.apiUrl}/servers/${id}`);
  }

  getDeployments() {
    return this.http.get<Deployment[]>(`${this.apiUrl}/deployments`);
  }

  getPlugins() {
    return this.http.get<Plugin[]>(`${this.apiUrl}/plugins`);
  }
}
