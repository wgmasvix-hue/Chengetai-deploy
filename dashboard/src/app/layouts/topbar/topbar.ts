import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../services/auth';

@Component({
  selector: 'app-topbar',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './topbar.html',
  styleUrl: './topbar.scss',
})
export class Topbar {
  auth = inject(AuthService);

  initials(): string {
    const email = this.auth.user()?.email || '';
    return email.slice(0, 2).toUpperCase();
  }

  logout() { this.auth.logout(); }
}
