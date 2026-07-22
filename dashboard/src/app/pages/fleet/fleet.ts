import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../services/api';
import { AuthService } from '../../services/auth';
import { FleetAgent, FleetCommand, EnrollmentToken } from '../../models/api.models';

// Remote commands the control plane accepts (mirrors the API's allow-list).
const REMOTE_COMMANDS = ['status', 'start', 'stop', 'restart', 'update', 'backup'];

@Component({
  selector: 'app-fleet',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './fleet.html',
  styleUrl: './fleet.scss',
})
export class Fleet implements OnInit, OnDestroy {
  private api = inject(ApiService);
  private auth = inject(AuthService);

  agents = signal<FleetAgent[]>([]);
  tokens = signal<EnrollmentToken[]>([]);
  error = signal('');
  notice = signal('');

  // Expanded agent row (command console + history).
  openAgent = signal<string | null>(null);
  commands = signal<FleetCommand[]>([]);
  commandChoices = REMOTE_COMMANDS;
  cmdDraft = { command: 'status', target: '' };

  // Enrollment-token issue form; the plaintext token is shown exactly once.
  showTokenForm = signal(false);
  tokenDraft = { label: '', ttlMinutes: 1440 };
  issuedToken = signal('');

  private timer: ReturnType<typeof setInterval> | null = null;

  get isAdmin() { return this.auth.user()?.role === 'admin'; }
  get canOperate() {
    const r = this.auth.user()?.role;
    return r === 'admin' || r === 'engineer';
  }

  ngOnInit(): void {
    this.load();
    // The fleet is live state — refresh alongside the heartbeat cadence.
    this.timer = setInterval(() => this.load(true), 30000);
  }
  ngOnDestroy(): void { if (this.timer) clearInterval(this.timer); }

  load(silent = false) {
    this.api.getFleetAgents().subscribe({
      next: (a) => this.agents.set(a),
      error: (err) => { if (!silent) this.error.set(err?.error?.error || 'Failed to load the fleet'); },
    });
    if (this.canOperate) {
      this.api.getEnrollmentTokens().subscribe({ next: (t) => this.tokens.set(t) });
    }
    const open = this.openAgent();
    if (open) this.loadCommands(open, true);
  }

  toggleAgent(a: FleetAgent) {
    if (this.openAgent() === a.id) { this.openAgent.set(null); return; }
    this.openAgent.set(a.id);
    this.commands.set([]);
    this.cmdDraft = { command: 'status', target: this.firstDeployment(a) };
    this.loadCommands(a.id);
  }

  loadCommands(agentId: string, silent = false) {
    this.api.getFleetCommands(agentId).subscribe({
      next: (c) => this.commands.set(c),
      error: (err) => { if (!silent) this.error.set(err?.error?.error || 'Failed to load commands'); },
    });
  }

  sendCommand(a: FleetAgent) {
    this.error.set('');
    const args = this.cmdDraft.target ? [this.cmdDraft.target] : [];
    this.api.queueFleetCommand(a.id, this.cmdDraft.command, args).subscribe({
      next: () => {
        this.notice.set(`Queued '${this.cmdDraft.command}' for ${a.name} — the agent picks it up on its next heartbeat.`);
        this.loadCommands(a.id);
      },
      error: (err) => this.error.set(err?.error?.error || 'Failed to queue the command'),
    });
  }

  revoke(a: FleetAgent) {
    if (!confirm(
      `KILL SWITCH — revoke ${a.name}?\n\nIts deployments will be stopped and the server can no longer deploy. Data is preserved; you can reactivate later.`,
    )) return;
    this.api.revokeFleetAgent(a.id).subscribe({
      next: () => { this.notice.set(`${a.name} revoked.`); this.load(); },
      error: (err) => this.error.set(err?.error?.error || 'Revoke failed'),
    });
  }

  reactivate(a: FleetAgent) {
    this.api.reactivateFleetAgent(a.id).subscribe({
      next: () => { this.notice.set(`${a.name} reactivated.`); this.load(); },
      error: (err) => this.error.set(err?.error?.error || 'Reactivate failed'),
    });
  }

  deregister(a: FleetAgent) {
    if (!confirm(`Remove ${a.name} from the fleet entirely? (The server itself is not touched.)`)) return;
    this.api.deregisterFleetAgent(a.id).subscribe({
      next: () => { this.notice.set(`${a.name} removed from the fleet.`); this.load(); },
      error: (err) => this.error.set(err?.error?.error || 'Remove failed'),
    });
  }

  issueToken() {
    this.error.set('');
    this.api.issueEnrollmentToken(this.tokenDraft).subscribe({
      next: (res) => {
        this.issuedToken.set(res.token);
        this.showTokenForm.set(false);
        this.tokenDraft = { label: '', ttlMinutes: 1440 };
        this.load();
      },
      error: (err) => this.error.set(err?.error?.error || 'Failed to issue a token'),
    });
  }

  enrollCommand(): string {
    const origin = typeof window !== 'undefined' ? window.location.origin : '<control-plane-url>';
    return `sudo chengetai enroll ${this.issuedToken()} --control-plane ${origin}`;
  }

  copyEnroll() {
    navigator.clipboard?.writeText(this.enrollCommand());
    this.notice.set('Enroll command copied — paste it on the new server. The token is shown only once.');
  }

  deployments(a: FleetAgent) { return a.lastStatus?.deployments || []; }
  firstDeployment(a: FleetAgent) { return this.deployments(a)[0]?.name || ''; }

  ago(iso: string | null | undefined): string {
    if (!iso) return 'never';
    const s = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 1000));
    if (s < 90) return `${s}s ago`;
    if (s < 5400) return `${Math.round(s / 60)}m ago`;
    if (s < 129600) return `${Math.round(s / 3600)}h ago`;
    return `${Math.round(s / 86400)}d ago`;
  }
}
