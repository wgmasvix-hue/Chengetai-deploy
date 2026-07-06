import { Component, inject, signal } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { ApiService } from '../../services/api';

@Component({
  selector: 'app-sidebar',
  standalone: true,
  imports: [RouterLink, RouterLinkActive],
  templateUrl: './sidebar.html',
  styleUrl: './sidebar.scss',
})
export class Sidebar {
  private api = inject(ApiService);
  version = signal('');
  constructor() {
    this.api.getHealth().subscribe({ next: (h) => this.version.set(h.version) });
  }
}
