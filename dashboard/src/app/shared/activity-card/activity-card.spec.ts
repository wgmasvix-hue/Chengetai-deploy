import { ComponentFixture, TestBed } from '@angular/core/testing';

import { ActivityCard } from './activity-card';

describe('ActivityCard', () => {
  let component: ActivityCard;
  let fixture: ComponentFixture<ActivityCard>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ActivityCard],
    }).compileComponents();

    fixture = TestBed.createComponent(ActivityCard);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
