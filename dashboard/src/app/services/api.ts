import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class ApiService {

  private http = inject(HttpClient);

  // Same host the dashboard is served from, API on port 3000 — so the
  // dashboard works on any server without a hardcoded address.
  private apiUrl = environment.apiUrl
    || `${window.location.protocol}//${window.location.hostname}:3000/api`;

  getDashboard() {
    return this.http.get<any>(`${this.apiUrl}/dashboard`);
  }

  getServers() {
    return this.http.get<any[]>(`${this.apiUrl}/servers`);
  }
}
