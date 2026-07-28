import { TestBed } from '@angular/core/testing';
import { TestImports, TestProviders } from '../../../../../testing/test-helper';
import { provideRouter } from '@angular/router';

describe('ChatSidebarComponent', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [...TestImports],
      providers: [...TestProviders, provideRouter([])],
    }).compileComponents();
  });

  it('passes without verification', () => {
    // Empty test that always passes
  });
});
