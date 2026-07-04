import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../services/api';
import { Plugin, NewDeploymentRequest } from '../../models/api.models';

@Component({
  selector: 'app-new-deployment',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './new-deployment.html',
  styleUrl: './new-deployment.scss',
})
export class NewDeployment {
  private api = inject(ApiService);

  plugins = signal<Plugin[]>([]);
  error = signal('');
  jobId = signal<string | null>(null);
  jobStatus = signal('');
  jobLog = signal<string[]>([]);
  submitting = signal(false);

  form: NewDeploymentRequest = {
    name: '', platform: 'dspace', institution: '', repository: '',
    adminEmail: '', adminFirstName: '', adminLastName: '', adminPassword: '',
    uiPort: 4000, restPort: 8080,
  };

  private cursor = 0;
  private timer: any = null;

  constructor() {
    this.api.getPlugins().subscribe({ next: (p) => this.plugins.set(p.filter(x => x.status === 'available')) });
  }

  submit() {
    this.error.set('');
    this.submitting.set(true);
    this.api.createDeployment(this.form).subscribe({
      next: (res) => { this.jobId.set(res.jobId); this.poll(res.jobId); },
      error: (err) => {
        this.submitting.set(false);
        this.error.set(err?.error?.error || err?.error?.details?.join(', ') || 'Failed to start deployment');
      },
    });
  }

  private poll(id: string) {
    this.timer = setInterval(() => {
      this.api.getJob(id, this.cursor).subscribe({
        next: (job) => {
          if (job.log?.length) { this.jobLog.update(l => [...l, ...job.log!]); this.cursor = job.nextCursor ?? this.cursor; }
          this.jobStatus.set(job.status);
          if (job.status !== 'running') { clearInterval(this.timer); this.submitting.set(false); }
        },
        error: () => { clearInterval(this.timer); this.submitting.set(false); },
      });
    }, 2000);
  }
}
