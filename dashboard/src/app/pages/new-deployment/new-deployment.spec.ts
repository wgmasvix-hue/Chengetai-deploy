import { ComponentFixture, TestBed } from '@angular/core/testing';

import { NewDeployment } from './new-deployment';

describe('NewDeployment', () => {
  let component: NewDeployment;
  let fixture: ComponentFixture<NewDeployment>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [NewDeployment],
    }).compileComponents();

    fixture = TestBed.createComponent(NewDeployment);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
