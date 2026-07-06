import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../services/api';
import { DashboardStats, Deployment } from '../../models/api.models';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.scss'
})
export class Dashboard implements OnInit {
  private api = inject(ApiService);

  stats = signal<DashboardStats | null>(null);
  deployments = signal<Deployment[]>([]);
  loading = signal(true);

  ngOnInit(): void {
    this.api.getDashboard().subscribe({
      next: (data) => { this.stats.set(data); this.loading.set(false); },
      error: () => this.loading.set(false)
    });
    this.api.getDeployments().subscribe({
      next: (data) => this.deployments.set(data)
    });
  }
}
