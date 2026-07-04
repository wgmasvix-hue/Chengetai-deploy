import { TestBed } from '@angular/core/testing';

import { Docker } from './docker';

describe('Docker', () => {
  let service: Docker;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(Docker);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
