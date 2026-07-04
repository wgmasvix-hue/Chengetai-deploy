import { Component } from '@angular/core';

import { Sidebar } from '../sidebar/sidebar';
import { Topbar } from '../topbar/topbar';
import { MobileNav } from '../mobile-nav/mobile-nav';
import { Dashboard } from '../../pages/dashboard/dashboard';

@Component({
  selector: 'app-main-layout',
  standalone: true,
  imports: [
    Sidebar,
    Topbar,
    MobileNav,
    Dashboard
  ],
  templateUrl: './main-layout.html',
  styleUrl: './main-layout.scss'
})
export class MainLayout {}
