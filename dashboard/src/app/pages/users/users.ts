import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../services/api';
import { User } from '../../models/api.models';

@Component({
  selector: 'app-users',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './users.html',
  styleUrl: './users.scss',
})
export class Users implements OnInit {
  private api = inject(ApiService);
  users = signal<User[]>([]);
  error = signal('');
  showForm = signal(false);
  draft = { email: '', password: '', role: 'viewer' };

  ngOnInit(): void { this.load(); }
  load() {
    this.api.getUsers().subscribe({
      next: (u) => this.users.set(u),
      error: (err) => this.error.set(err?.error?.error || 'Failed to load users'),
    });
  }
  add() {
    this.error.set('');
    this.api.createUser(this.draft).subscribe({
      next: () => { this.showForm.set(false); this.draft = { email: '', password: '', role: 'viewer' }; this.load(); },
      error: (err) => this.error.set(err?.error?.error || err?.error?.details?.join(', ') || 'Failed'),
    });
  }
  setRole(u: User, role: string) { this.api.updateUser(u.id, { role }).subscribe({ next: () => this.load() }); }
  remove(u: User) {
    if (!confirm(`Remove user ${u.email}?`)) return;
    this.api.deleteUser(u.id).subscribe({ next: () => this.load(), error: (err) => this.error.set(err?.error?.error || 'Failed') });
  }
}
