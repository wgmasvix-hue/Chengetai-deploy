import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../services/api';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.scss'
})
export class Dashboard implements OnInit {

  private api = inject(ApiService);

  dashboard:any = {};
  servers:any[] = [];

  ngOnInit(): void {
    console.log('Loading dashboard...');

    this.api.getDashboard().subscribe({
      next: (data) => {
        console.log('Dashboard:', data);
        this.dashboard = data;
      },
      error: (err) => {
        console.error('Dashboard error:', err);
      }
    });

    this.api.getServers().subscribe({
      next: (data) => {
        console.log('Servers:', data);
        this.servers = data;
      },
      error: (err) => {
        console.error('Servers error:', err);
      }
    });
  }

}
