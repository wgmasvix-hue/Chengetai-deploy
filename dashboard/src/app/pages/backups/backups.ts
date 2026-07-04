import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ApiService } from '../../services/api';
import { Deployment } from '../../models/api.models';

@Component({
  selector: 'app-backups',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './backups.html',
  styleUrl: './backups.scss',
})
export class Backups implements OnInit {
  private api = inject(ApiService);
  deployments = signal<Deployment[]>([]);
  jobLog = signal<string[]>([]);
  jobStatus = signal('');
  activeName = signal('');
  private cursor = 0;
  private timer: any = null;

  ngOnInit(): void {
    this.api.getDeployments().subscribe({ next: (d) => this.deployments.set(d) });
  }

  backup(d: Deployment) {
    this.jobLog.set([]); this.cursor = 0; this.jobStatus.set('running'); this.activeName.set(d.name);
    this.api.deploymentAction(d.name, 'backup').subscribe({
      next: (res) => this.poll(res.jobId),
      error: (err) => { this.jobStatus.set('failed'); this.jobLog.set([err?.error?.error || 'Failed to start backup']); },
    });
  }

  private poll(id: string) {
    this.timer = setInterval(() => {
      this.api.getJob(id, this.cursor).subscribe({
        next: (job) => {
          if (job.log?.length) { this.jobLog.update(l => [...l, ...job.log!]); this.cursor = job.nextCursor ?? this.cursor; }
          this.jobStatus.set(job.status);
          if (job.status !== 'running') clearInterval(this.timer);
        },
        error: () => clearInterval(this.timer),
      });
    }, 2000);
  }
}
