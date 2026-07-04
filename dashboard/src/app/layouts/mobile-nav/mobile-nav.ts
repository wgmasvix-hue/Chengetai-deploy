import { Component } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';

@Component({
  selector: 'app-mobile-nav',
  standalone: true,
  imports: [RouterLink, RouterLinkActive],
  templateUrl: './mobile-nav.html',
  styleUrl: './mobile-nav.scss',
})
export class MobileNav {}
