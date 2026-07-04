import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class ApiService {

  private http = inject(HttpClient);

  getDashboard() {
    return this.http.get<any>(`${environment.apiUrl}/dashboard`);
  }

  getServers() {
    return this.http.get<any[]>(`${environment.apiUrl}/servers`);
  }
}
