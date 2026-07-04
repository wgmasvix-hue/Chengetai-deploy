import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../services/api';
import { Deployment } from '../../models/api.models';

@Component({
  selector: 'app-deployments',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './deployments.html',
  styleUrl: './deployments.scss'
})
export class Deployments implements OnInit {
  private api = inject(ApiService);
  deployments = signal<Deployment[]>([]);

  ngOnInit(): void {
    this.api.getDeployments().subscribe({ next: (d) => this.deployments.set(d) });
  }
}
