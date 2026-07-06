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
  busy = signal<string>('');       // "name:action" currently running
  notice = signal<string>('');

  ngOnInit(): void { this.load(); }
  load() { this.api.getDeployments().subscribe({ next: (d) => this.deployments.set(d) }); }

  act(d: Deployment, action: string) {
    this.notice.set('');
    this.busy.set(`${d.name}:${action}`);
    this.api.deploymentAction(d.name, action).subscribe({
      next: () => { this.busy.set(''); this.notice.set(`${action} started for ${d.name}.`); },
      error: (err) => { this.busy.set(''); this.notice.set(err?.error?.error || `Failed to ${action} ${d.name}`); },
    });
  }

  remove(d: Deployment) {
    if (!confirm(`Remove deployment "${d.name}"? (data volumes are kept)`)) return;
    this.busy.set(`${d.name}:remove`);
    this.api.deleteDeployment(d.name, false).subscribe({
      next: () => { this.busy.set(''); this.notice.set(`Removal started for ${d.name}.`); setTimeout(() => this.load(), 3000); },
      error: (err) => { this.busy.set(''); this.notice.set(err?.error?.error || 'Failed to remove'); },
    });
  }

  isBusy(d: Deployment, action: string) { return this.busy() === `${d.name}:${action}`; }
}
