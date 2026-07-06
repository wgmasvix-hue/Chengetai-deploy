import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../services/api';
import { ServerInfo } from '../../models/api.models';

@Component({
  selector: 'app-server',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './server.html',
  styleUrl: './server.scss'
})
export class Server implements OnInit {
  private api = inject(ApiService);

  servers = signal<ServerInfo[]>([]);
  showForm = signal(false);
  error = signal('');
  draft: Partial<ServerInfo> = { port: 22, authMethod: 'ssh-key' };

  ngOnInit(): void { this.load(); }

  load() {
    this.api.getServers().subscribe({
      next: (data) => this.servers.set(data),
      error: (err) => this.error.set(err?.error?.error || 'Failed to load servers')
    });
  }

  add() {
    this.error.set('');
    this.api.addServer(this.draft).subscribe({
      next: () => { this.showForm.set(false); this.draft = { port: 22, authMethod: 'ssh-key' }; this.load(); },
      error: (err) => this.error.set(err?.error?.details?.join(', ') || err?.error?.error || 'Failed to add server')
    });
  }

  remove(s: ServerInfo) {
    if (!confirm(`Remove server "${s.name}"?`)) return;
    this.api.deleteServer(s.id).subscribe({ next: () => this.load() });
  }
}
