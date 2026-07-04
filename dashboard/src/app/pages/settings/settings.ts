import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../services/api';
import { AuthService } from '../../services/auth';

@Component({
  selector: 'app-settings',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './settings.html',
  styleUrl: './settings.scss',
})
export class Settings {
  private api = inject(ApiService);
  auth = inject(AuthService);

  currentPassword = '';
  newPassword = '';
  message = signal('');
  error = signal('');

  changePassword() {
    this.message.set(''); this.error.set('');
    this.api.changePassword(this.currentPassword, this.newPassword).subscribe({
      next: () => { this.message.set('Password changed.'); this.currentPassword = ''; this.newPassword = ''; },
      error: (err) => this.error.set(err?.error?.error || err?.error?.details?.join(', ') || 'Failed'),
    });
  }
}
