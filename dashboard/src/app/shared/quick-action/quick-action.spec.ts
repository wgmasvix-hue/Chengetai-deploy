import { ComponentFixture, TestBed } from '@angular/core/testing';

import { QuickAction } from './quick-action';

describe('QuickAction', () => {
  let component: QuickAction;
  let fixture: ComponentFixture<QuickAction>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [QuickAction],
    }).compileComponents();

    fixture = TestBed.createComponent(QuickAction);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
