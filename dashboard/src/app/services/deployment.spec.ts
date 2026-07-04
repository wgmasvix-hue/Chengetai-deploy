import { TestBed } from '@angular/core/testing';

import { Deployment } from './deployment';

describe('Deployment', () => {
  let service: Deployment;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(Deployment);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
