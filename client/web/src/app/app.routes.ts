import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    path: '',
    loadComponent: () => import('./features/chat/chat.component').then((m) => m.ChatComponent),
    data: { preload: 'critical' },
  },
  {
    path: 'private/:code',
    loadComponent: () => import('./features/chat/chat.component').then((m) => m.ChatComponent),
    data: { preload: 'critical' },
  },
  {
    path: '404',
    loadComponent: () =>
      import('./features/not-found/not-found.component').then((m) => m.NotFoundComponent),
  },
  {
    path: 'acknowledgements',
    loadComponent: () =>
      import('./features/acknowledgements/acknowledgements.component').then(
        (m) => m.AcknowledgementsComponent
      ),
  },
  {
    path: 'privacy',
    loadComponent: () =>
      import('./features/privacy-and-terms/privacy-and-terms.component').then(
        (m) => m.PrivacyAndTermsComponent
      ),
  },
  { path: '**', redirectTo: '404' },
];
